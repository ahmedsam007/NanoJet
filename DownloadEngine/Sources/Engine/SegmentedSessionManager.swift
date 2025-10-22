import Foundation

public final class SegmentedSessionManager: NSObject, URLSessionManaging {
    private struct Inflight {
        var tasks: [URLSessionTask] = []
        var tempFileURL: URL
        var totalBytes: Int64
        var segments: [Segment]
        var isCanceled: Bool = false
        var isFinalized: Bool = false
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var itemIdToInflight: [UUID: Inflight] = [:]
    private var taskIdToItemId: [Int: UUID] = [:]
    private var taskIdToSegmentIndex: [Int: Int] = [:]
    private var taskIdToExpectedStart: [Int: Int64] = [:]
    private var taskIdToResumeFileURL: [Int: URL] = [:]
    // Serialize access to task/segment maps to avoid concurrent dictionary mutations
    private let stateQueue = DispatchQueue(label: "segmented.session.state")
    private var itemIdToWriteQueue: [UUID: DispatchQueue] = [:]
    private var itemIdToSpeedMeter: [UUID: SpeedMeter] = [:]
    private var itemIdToSegmentReceived: [UUID: [Int: Int64]] = [:]
    private var itemIdToRetryCounts: [UUID: [Int: Int]] = [:]
    private var itemIdToRangeRejectCounts: [UUID: [Int: Int]] = [:]
    private let maxRangeRejectsPerSegment: Int = 3
    // Track last logged progress per segment to avoid ultra-verbose logs
    private var itemIdToLastLoggedSegmentReceived: [UUID: [Int: Int64]] = [:]
    private var itemIdToRequestHeaders: [UUID: [String: String]] = [:]
    // Force single-task download for items that reject ranged requests (e.g., googlevideo 403)
    private var itemIdsForcedSingle: Set<UUID> = []
    private var itemIdsSingleStarted: Set<UUID> = []
    // Resume data for fallback single-downloads
    private var itemIdToResumeData: [UUID: Data] = [:]
    private let maxRetriesPerSegment: Int = 5
    private weak var coordinatorRef: DownloadCoordinator?
    // Track items for which we've already attempted a YouTube URL refresh to avoid loops
    private var itemIdsYTRefreshAttempted: Set<UUID> = []
    // Track items that have partial segment data to prevent overwriting via single download
    private var itemIdsWithPartialSegmentData: Set<UUID> = []

    public func setCoordinator(_ coordinator: DownloadCoordinator) {
        self.coordinatorRef = coordinator
    }

    public func startDownload(for item: DownloadItem) async {
        let itemId = item.id
        // Capture headers for reuse across retries and segments
        if let headers = item.requestHeaders { itemIdToRequestHeaders[itemId] = headers } else { itemIdToRequestHeaders[itemId] = [:] }
        DownloadLogger.log(itemId: itemId, "startDownload(segmented): url=\(item.url)")
        // Avoid duplicate concurrent starts for the same item. If an inflight download
        // is already active and not canceled/finalized, ignore this call.
        if let existing = stateQueue.sync(execute: { itemIdToInflight[itemId] }), !existing.isCanceled, !existing.isFinalized {
            DownloadLogger.log(itemId: itemId, "startDownload ignored: already inflight")
            return
        }
        // Probe for range support and content length
        do {
            let (supportsRanges, totalBytes) = try await probe(item: item)
            DownloadLogger.log(itemId: itemId, "probe: supportsRanges=\(supportsRanges) totalBytes=\(totalBytes)")
            if !supportsRanges || totalBytes <= 0 {
                // For YouTube direct links, try to refresh a stale URL once via yt-dlp before falling back
                if let host = item.url.host?.lowercased(), host.contains("googlevideo.com"), !itemIdsYTRefreshAttempted.contains(itemId) {
                    itemIdsYTRefreshAttempted.insert(itemId)
                    if await refreshYouTubeURLIfPossible(itemId: itemId), let updated = await coordinatorRef?.getItem(id: itemId) {
                        DownloadLogger.log(itemId: itemId, "probe failed; refreshed YouTube URL. Restarting download")
                        await startDownload(for: updated)
                        return
                    }
                }
                // If we have partial segment data, don't overwrite with single download
                if itemIdsWithPartialSegmentData.contains(itemId) {
                    DownloadLogger.log(itemId: itemId, "probe failed but partial segment data exists; failing to prevent data loss")
                    await updateItem(itemId) { i in
                        i.status = .failed
                        i.lastError = "Server probe failed (no range support or invalid response). Cannot resume segmented download. The server may have changed the file or the download link may have expired."
                    }
                    return
                }
                // Fallback: single download using downloadTask so we can pause/resume
                DownloadLogger.log(itemId: itemId, "probe indicates no range support → fallback to single download task")
                await startSingleDownloadTask(item: item)
                return
            }

            // Determine segments: reuse persisted segments if available; otherwise compute new
            // Choose chunk count based on total size (2..8)
            let numSegments = decideSegmentCount(totalBytes: totalBytes)
            let shouldReuseExisting = (item.segments?.isEmpty == false) && (item.totalBytes == nil || item.totalBytes == totalBytes)
            let segments: [Segment] = shouldReuseExisting ? (item.segments ?? []) : makeSegments(totalBytes: totalBytes, count: numSegments)

            // Prepare temp file without destroying existing partial data
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("seg_\(item.id).bin")
            if !FileManager.default.fileExists(atPath: temp.path) {
                _ = try preallocateEmptyFile(at: temp, size: totalBytes)
            }

            let inflight = Inflight(tasks: [], tempFileURL: temp, totalBytes: totalBytes, segments: segments)
            itemIdToInflight[itemId] = inflight
            itemIdToWriteQueue[itemId] = DispatchQueue(label: "segmented.write.\(itemId)")
            itemIdToSpeedMeter[itemId] = SpeedMeter()
            // Initialize received map from existing segment progress when reusing
            if shouldReuseExisting {
                itemIdToSegmentReceived[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.received) })
            } else {
                itemIdToSegmentReceived[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            }
            itemIdToRetryCounts[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            itemIdToRangeRejectCounts[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            // Mark this item as having segmented download in progress
            itemIdsWithPartialSegmentData.insert(itemId)

            // Update status to downloading AND set segments atomically
            // This ensures UI shows "Downloading" with visible chunks immediately
            await updateItem(itemId) { i in
                i.status = .downloading
                i.totalBytes = totalBytes
                i.supportsRanges = true
                i.segments = segments
                let totalReceived = segments.reduce(Int64(0)) { $0 + $1.received }
                i.receivedBytes = totalReceived
            }

            // Launch parallel data tasks, continuing from already received byte offsets when resuming
            var launchedAnyTask = false
            for seg in segments {
                let segmentLength = seg.rangeEnd - seg.rangeStart + 1
                let alreadyRaw = itemIdToSegmentReceived[itemId]?[seg.index] ?? 0
                let already = max(0, min(alreadyRaw, segmentLength))
                // If this segment is already fully received, skip launching a task
                if already >= segmentLength { continue }
                var req = URLRequest(url: item.url)
                req.httpMethod = "GET"
                req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if let headers = itemIdToRequestHeaders[itemId] {
                    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                    let cookiePresent = headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame })
                    let referer = headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value ?? ""
                    DownloadLogger.log(itemId: itemId, "using headers: Referer=\(referer.isEmpty ? "<none>" : referer) Cookie=\(cookiePresent ? "present" : "absent")")
                }
                if let h = req.url?.host?.lowercased(), h.contains("googlevideo.com") {
                    // Strip cookies to avoid cross-domain auth causing 403
                    if req.value(forHTTPHeaderField: "Cookie") != nil { req.setValue(nil, forHTTPHeaderField: "Cookie") }
                    req.httpShouldHandleCookies = false
                    if req.value(forHTTPHeaderField: "Referer") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
                    if req.value(forHTTPHeaderField: "Origin") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
                    if req.value(forHTTPHeaderField: "User-Agent") == nil {
                        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                    }
                    if req.value(forHTTPHeaderField: "Accept") == nil { req.setValue("*/*", forHTTPHeaderField: "Accept") }
                    if req.value(forHTTPHeaderField: "Accept-Language") == nil { req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language") }
                }
                // Log effective headers after normalization
                do {
                    let cookiePresentEff = (req.value(forHTTPHeaderField: "Cookie") != nil)
                    let refererEff = req.value(forHTTPHeaderField: "Referer") ?? ""
                    DownloadLogger.log(itemId: itemId, "using headers: Referer=\(refererEff.isEmpty ? "<none>" : refererEff) Cookie=\(cookiePresentEff ? "present" : "absent")")
                }
                let start = seg.rangeStart + already
                let range = ByteRange(start: start, end: seg.rangeEnd)
                req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                DownloadLogger.log(itemId: itemId, "launch segment #\(seg.index) range=\(range) already=\(already)")
                let task = session.dataTask(with: req)
                stateQueue.async { [weak self] in
                    guard let self else { return }
                    self.taskIdToItemId[task.taskIdentifier] = itemId
                    self.taskIdToSegmentIndex[task.taskIdentifier] = seg.index
                    self.taskIdToExpectedStart[task.taskIdentifier] = start
                    if var inflight = self.itemIdToInflight[itemId] {
                        inflight.tasks.append(task)
                        self.itemIdToInflight[itemId] = inflight
                    }
                }
                task.resume()
                launchedAnyTask = true
            }
            // If all segments were already complete (e.g., resuming from persisted state), try to finalize now
            if !launchedAnyTask {
                DownloadLogger.log(itemId: itemId, "all segments already complete; attempting finalize")
                tryFinalizeIfComplete(itemId: itemId)
            }
        } catch {
            await updateItem(itemId) { i in
                i.status = .failed
                i.lastError = error.localizedDescription
            }
            DownloadLogger.log(itemId: itemId, "startDownload error: \(error.localizedDescription)")
        }
    }

    public func pauseDownload(for item: DownloadItem) async {
        let itemId = item.id
        DownloadLogger.log(itemId: itemId, "pauseDownload(segmented)")
        if var inflight = itemIdToInflight[itemId] {
            inflight.isCanceled = true
            // Clear all tasks to prevent duplicate task accumulation on resume
            let tasksToCancel = inflight.tasks
            inflight.tasks = []
            itemIdToInflight[itemId] = inflight
            tasksToCancel.forEach { $0.cancel() }
            // Save current segment progress to item BEFORE marking as paused
            await updateItem(itemId) { i in
                if var segs = i.segments {
                    for idx in segs.indices {
                        let segIndex = segs[idx].index
                        if let received = self.itemIdToSegmentReceived[itemId]?[segIndex] {
                            let need = segs[idx].rangeEnd - segs[idx].rangeStart + 1
                            segs[idx].received = min(need, received)
                            DownloadLogger.log(itemId: itemId, "pause: saving segment #\(segIndex) progress: \(segs[idx].received)/\(need)")
                        }
                    }
                    i.segments = segs
                }
                i.status = .paused
            }
        } else {
            // Fallback single download: cancel with resume data
            let semaphore = DispatchSemaphore(value: 0)
            session.getAllTasks { tasks in
                let tasksForItem = tasks.filter { self.taskIdToItemId[$0.taskIdentifier] == itemId }
                if tasksForItem.isEmpty { semaphore.signal(); return }
                for t in tasksForItem {
                    if let dlt = t as? URLSessionDownloadTask {
                        dlt.cancel(byProducingResumeData: { data in
                            if let data { self.itemIdToResumeData[itemId] = data }
                            semaphore.signal()
                        })
                    } else {
                        t.cancel()
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
            await updateItem(itemId) { i in i.status = .paused }
        }
    }

    public func resumeDownload(for item: DownloadItem) async {
        let itemId = item.id
        DownloadLogger.log(itemId: itemId, "resumeDownload(segmented)")
        
        // Prevent duplicate resume calls: if already downloading, ignore
        if let existing = itemIdToInflight[itemId], !existing.isCanceled, !existing.isFinalized {
            let hasActiveTasks = !existing.tasks.isEmpty
            if hasActiveTasks {
                DownloadLogger.log(itemId: itemId, "resumeDownload ignored: already downloading with active tasks")
                return
            }
        }
        
        // Resume fallback single download if we have resume data
        if let data = itemIdToResumeData[itemId] {
            let task = session.downloadTask(withResumeData: data)
            stateQueue.async { [weak self] in
                guard let self else { return }
                self.taskIdToItemId[task.taskIdentifier] = itemId
                self.itemIdToResumeData[itemId] = nil
            }
            if itemIdToSpeedMeter[itemId] == nil { itemIdToSpeedMeter[itemId] = SpeedMeter() }
            await updateItem(itemId) { i in i.status = .reconnecting }
            task.resume()
            return
        }
        
        // If no inflight state exists but item has segments (paused segmented download),
        // reconstruct inflight state from persisted item data
        if itemIdToInflight[itemId] == nil, let segments = item.segments, !segments.isEmpty, let totalBytes = item.totalBytes {
            DownloadLogger.log(itemId: itemId, "reconstructing inflight state from persisted segments")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("seg_\(item.id).bin")
            // Verify temp file exists; if not, must restart from scratch
            if !FileManager.default.fileExists(atPath: temp.path) {
                DownloadLogger.log(itemId: itemId, "temp file missing; restarting download")
                await startDownload(for: item)
                return
            }
            let inflight = Inflight(tasks: [], tempFileURL: temp, totalBytes: totalBytes, segments: segments)
            itemIdToInflight[itemId] = inflight
            itemIdToWriteQueue[itemId] = DispatchQueue(label: "segmented.write.\(itemId)")
            itemIdToSpeedMeter[itemId] = SpeedMeter()
            itemIdToSegmentReceived[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.received) })
            itemIdToRetryCounts[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            itemIdToRangeRejectCounts[itemId] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            // Mark this item as having partial segment data (resumed from pause)
            itemIdsWithPartialSegmentData.insert(itemId)
        }
        
        // Resume segmented by re-starting remaining segments (those not "done")
        guard var inflight = itemIdToInflight[itemId] else {
            // No segments or totalBytes available; must restart
            DownloadLogger.log(itemId: itemId, "no inflight state or segments; restarting download")
            await startDownload(for: item)
            return
        }
        
        // CRITICAL: Update inflight.segments with the saved progress from item.segments
        // During pause, segment progress is saved to item.segments, but inflight.segments
        // is not updated. If we don't sync here, resume will use stale received=0 values
        // and overwrite already-downloaded data, causing file corruption!
        if let savedSegments = item.segments, !savedSegments.isEmpty {
            DownloadLogger.log(itemId: itemId, "syncing inflight segments with saved progress from pause")
            inflight.segments = savedSegments
            itemIdToInflight[itemId] = inflight
            // Also update the in-memory tracking map
            itemIdToSegmentReceived[itemId] = Dictionary(uniqueKeysWithValues: savedSegments.map { ($0.index, $0.received) })
        }
        
        // Clear canceled flag so new retries/receives proceed
        if inflight.isCanceled {
            inflight.isCanceled = false
            itemIdToInflight[itemId] = inflight
        }
        let remaining: [Segment] = inflight.segments.filter { $0.received < ($0.rangeEnd - $0.rangeStart + 1) }
        // Ensure retry and reject counts maps exist for all segments
        if itemIdToRetryCounts[itemId] == nil {
            itemIdToRetryCounts[itemId] = Dictionary(uniqueKeysWithValues: inflight.segments.map { ($0.index, 0) })
        }
        if itemIdToRangeRejectCounts[itemId] == nil {
            itemIdToRangeRejectCounts[itemId] = Dictionary(uniqueKeysWithValues: inflight.segments.map { ($0.index, 0) })
        }
        if remaining.isEmpty {
            // All segments already fully received; finalize now
            // Use shared finalization helper to avoid races and failed status overrides
            tryFinalizeIfComplete(itemId: itemId)
            return
        }
        // Show reconnecting until we actually receive bytes
        await updateItem(itemId) { i in i.status = .reconnecting }
        // Relaunch data tasks for remaining segments
        for seg in remaining {
            let totalLen = seg.rangeEnd - seg.rangeStart + 1
            let got = max(0, min(seg.received, totalLen))
            if got >= totalLen { continue }
            var req = URLRequest(url: item.url)
            req.httpMethod = "GET"
            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if let headers = itemIdToRequestHeaders[itemId] { for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) } }
            if let h = req.url?.host?.lowercased(), h.contains("googlevideo.com") {
                if req.value(forHTTPHeaderField: "Referer") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
                if req.value(forHTTPHeaderField: "Origin") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
                if req.value(forHTTPHeaderField: "User-Agent") == nil {
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                }
            }
            let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
            req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
            let task = session.dataTask(with: req)
            stateQueue.async { [weak self] in
                guard let self else { return }
                self.taskIdToItemId[task.taskIdentifier] = itemId
                self.taskIdToSegmentIndex[task.taskIdentifier] = seg.index
                self.taskIdToExpectedStart[task.taskIdentifier] = seg.rangeStart + got
                if var inflight = self.itemIdToInflight[itemId] {
                    inflight.tasks.append(task)
                    self.itemIdToInflight[itemId] = inflight
                }
            }
            task.resume()
        }
    }

    public func cancelDownload(for item: DownloadItem) async {
        let itemId = item.id
        DownloadLogger.log(itemId: itemId, "cancelDownload(segmented)")
        if var inflight = itemIdToInflight[itemId] {
            inflight.isCanceled = true
            itemIdToInflight[itemId] = inflight
            inflight.tasks.forEach { $0.cancel() }
        }
        // Clear partial data flag on cancel
        itemIdsWithPartialSegmentData.remove(itemId)
        await updateItem(itemId) { i in i.status = .canceled }
    }

    private func probe(item: DownloadItem) async throws -> (Bool, Int64) {
        let url = item.url
        // Special-case googlevideo.com (YouTube):
        // - HEAD frequently returns 403
        // - Prefer using 'clen' when present, otherwise probe via a tiny ranged GET with proper headers
        if let host = url.host?.lowercased(), host.contains("googlevideo.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let clenStr = comps.queryItems?.first(where: { $0.name == "clen" })?.value,
               let clen = Int64(clenStr) {
                return (true, clen)
            }
            var r = URLRequest(url: url)
            r.httpMethod = "GET"
            r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            r.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            if let headers = itemIdToRequestHeaders[item.id] ?? item.requestHeaders {
                for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
            }
            // Clean YouTube probe headers (no cookies); add typical browser headers
            if r.value(forHTTPHeaderField: "Cookie") != nil { r.setValue(nil, forHTTPHeaderField: "Cookie") }
            r.httpShouldHandleCookies = false
            if r.value(forHTTPHeaderField: "Referer") == nil { r.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
            if r.value(forHTTPHeaderField: "Origin") == nil { r.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
            if r.value(forHTTPHeaderField: "User-Agent") == nil {
                r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            }
            if r.value(forHTTPHeaderField: "Accept") == nil { r.setValue("*/*", forHTTPHeaderField: "Accept") }
            if r.value(forHTTPHeaderField: "Accept-Language") == nil { r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language") }
            let (_, rresp) = try await session.data(for: r)
            if let h = rresp as? HTTPURLResponse {
                if h.statusCode == 206 {
                    let len = h.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) } ?? 0
                    DownloadLogger.log(itemId: item.id, "probe tiny GET status=\(h.statusCode) total=\(len)")
                    return (true, len)
                } else if h.statusCode == 403 {
                    // Googlevideo may block probe requests; treat as unknown rather than forcing single immediately
                    DownloadLogger.log(itemId: item.id, "probe tiny GET returned 403; treating as unknown length")
                    return (false, 0)
                } else {
                    let cr = h.value(forHTTPHeaderField: "Content-Range") ?? ""
                    DownloadLogger.log(itemId: item.id, "probe tiny GET status=\(h.statusCode) content-range=\(cr)")
                    // Retry with a slightly larger initial range, some CDNs reject 0-0
                    var r2 = r
                    r2.setValue("bytes=0-1", forHTTPHeaderField: "Range")
                    let (_, rresp2) = try await session.data(for: r2)
                    if let h2 = rresp2 as? HTTPURLResponse {
                        if h2.statusCode == 206 {
                            let len2 = h2.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) } ?? 0
                            DownloadLogger.log(itemId: item.id, "probe tiny GET(0-1) status=\(h2.statusCode) total=\(len2)")
                            return (true, len2)
                        } else if h2.statusCode == 403 {
                            DownloadLogger.log(itemId: item.id, "probe tiny GET(0-1) returned 403; treating as unknown length")
                            return (false, 0)
                        } else {
                            let cr2 = h2.value(forHTTPHeaderField: "Content-Range") ?? ""
                            DownloadLogger.log(itemId: item.id, "probe tiny GET(0-1) status=\(h2.statusCode) content-range=\(cr2)")
                        }
                    }
                }
            }
            // We could not establish total length; allow fallback to single-task which also applies YT headers
            return (false, 0)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let headers = itemIdToRequestHeaders[item.id] ?? item.requestHeaders {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return (false, 0) }
        let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
        let lenStr = http.value(forHTTPHeaderField: "Content-Length") ?? "0"
        let total = Int64(lenStr) ?? 0
        DownloadLogger.log(itemId: item.id, "probe HEAD status=\(http.statusCode) acceptRanges=\(acceptRanges) contentLength=\(total)")
        if acceptRanges && total > 0 { return (true, total) }
        // Fallback: tiny ranged GET to check 206
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        r.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let headers = itemIdToRequestHeaders[item.id] ?? item.requestHeaders {
            for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        }
        let (_, rresp) = try await session.data(for: r)
        if let h = rresp as? HTTPURLResponse, h.statusCode == 206 {
            let len = h.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) } ?? total
            DownloadLogger.log(itemId: item.id, "probe tiny GET status=\(h.statusCode) total=\(len)")
            return (true, len)
        }
        return (false, total)
    }

    private func makeSegments(totalBytes: Int64, count: Int) -> [Segment] {
        var segments: [Segment] = []
        let base = totalBytes / Int64(count)
        var start: Int64 = 0
        for idx in 0..<count {
            var end = start + base - 1
            if idx == count - 1 { end = totalBytes - 1 }
            segments.append(Segment(index: idx, rangeStart: start, rangeEnd: end, received: 0, state: "queued"))
            start = end + 1
        }
        return segments
    }

    // Decide number of segments based on file size. Tuned for good parallelism without excess overhead.
    private func decideSegmentCount(totalBytes: Int64) -> Int {
        let mb = totalBytes / (1024 * 1024)
        switch mb {
        case ..<20:   return 2     // < 20 MB → 2 chunks
        case 20..<100: return 4     // 20–99 MB → 4 chunks
        case 100..<500: return 6    // 100–499 MB → 6 chunks
        default:       return 8     // ≥ 500 MB → 8 chunks
        }
    }

    // streaming via delegate below

    private func startSingleDownloadTask(item: DownloadItem) async {
        let itemId = item.id
        DownloadLogger.log(itemId: itemId, "startSingleDownloadTask")
        var req = URLRequest(url: item.url)
        req.httpMethod = "GET"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let headers = itemIdToRequestHeaders[itemId] ?? item.requestHeaders {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let cookiePresent = headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame })
            let referer = headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value ?? ""
            DownloadLogger.log(itemId: itemId, "using headers: Referer=\(referer.isEmpty ? "<none>" : referer) Cookie=\(cookiePresent ? "present" : "absent")")
        }
        if let h = req.url?.host?.lowercased(), h.contains("googlevideo.com") {
            // Strip cookies to avoid cross-domain auth causing 403
            if req.value(forHTTPHeaderField: "Cookie") != nil { req.setValue(nil, forHTTPHeaderField: "Cookie") }
            req.httpShouldHandleCookies = false
            if req.value(forHTTPHeaderField: "Referer") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
            if req.value(forHTTPHeaderField: "Origin") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
            if req.value(forHTTPHeaderField: "User-Agent") == nil {
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            }
            if req.value(forHTTPHeaderField: "Accept") == nil { req.setValue("*/*", forHTTPHeaderField: "Accept") }
            if req.value(forHTTPHeaderField: "Accept-Language") == nil { req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language") }
            // Some googlevideo endpoints prefer ranged requests for direct downloads
            if req.value(forHTTPHeaderField: "Range") == nil { req.setValue("bytes=0-", forHTTPHeaderField: "Range") }
        }
        // Log effective headers after normalization
        do {
            let cookiePresentEff = (req.value(forHTTPHeaderField: "Cookie") != nil)
            let refererEff = req.value(forHTTPHeaderField: "Referer") ?? ""
            DownloadLogger.log(itemId: itemId, "using headers: Referer=\(refererEff.isEmpty ? "<none>" : refererEff) Cookie=\(cookiePresentEff ? "present" : "absent")")
        }
        let task = session.downloadTask(with: req)
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.taskIdToItemId[task.taskIdentifier] = itemId
        }
        if itemIdToSpeedMeter[itemId] == nil { itemIdToSpeedMeter[itemId] = SpeedMeter() }
        await updateItem(itemId) { i in
            i.status = .downloading
            i.supportsRanges = false
        }
        task.resume()
    }

    private func updateItem(_ id: UUID, mutate: @escaping (inout DownloadItem) -> Void) async {
        guard let coord = coordinatorRef else { return }
        if var item = await coord.getItem(id: id) {
            mutate(&item)
            await coord.handleProgressUpdate(item)
        }
    }

    // Attempt to finalize: move temp file to Downloads and mark completed. Does nothing if not fully received.
    private func tryFinalizeIfComplete(itemId: UUID) {
        guard var inflight = itemIdToInflight[itemId], !inflight.isCanceled, !inflight.isFinalized else { return }
        let allDone = inflight.segments.allSatisfy { seg in
            let got = itemIdToSegmentReceived[itemId]?[seg.index] ?? 0
            let need = seg.rangeEnd - seg.rangeStart + 1
            return got >= need
        }
        if !allDone { return }
        
        // Validate file size matches expected total before finalizing
        if let attrs = try? FileManager.default.attributesOfItem(atPath: inflight.tempFileURL.path),
           let fileSize = attrs[.size] as? Int64 {
            if fileSize != inflight.totalBytes {
                DownloadLogger.log(itemId: itemId, "finalize aborted: file size mismatch (expected=\(inflight.totalBytes) actual=\(fileSize))")
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateItem(itemId) { item in
                        item.status = .failed
                        item.lastError = "File size mismatch: expected \(inflight.totalBytes) bytes but got \(fileSize) bytes. The file may be corrupted."
                    }
                }
                return
            }
        } else {
            DownloadLogger.log(itemId: itemId, "finalize aborted: could not read temp file attributes")
            Task { [weak self] in
                guard let self else { return }
                await self.updateItem(itemId) { item in
                    item.status = .failed
                    item.lastError = "Could not verify downloaded file integrity."
                }
            }
            return
        }
        
        inflight.isFinalized = true
        itemIdToInflight[itemId] = inflight
        Task { [weak self] in
            guard let self, let coord = self.coordinatorRef else { return }
            let item = await coord.getItem(id: itemId)
            let suggested = item?.finalFileName
            let fileName = suggested ?? item?.url.lastPathComponent ?? "download.bin"
            do {
                // Try user-preferred directory via bookmark if set on the item
                let preferredDir: URL? = {
                    if let bookmark = item?.destinationDirBookmark {
                        var isStale = false
                        if let dir = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                            let started = dir.startAccessingSecurityScopedResource()
                            defer { if started { dir.stopAccessingSecurityScopedResource() } }
                            return dir
                        }
                    }
                    return nil
                }()
                // Keep security scope active during move
                let started = preferredDir?.startAccessingSecurityScopedResource() ?? false
                let final = try FileMover.move(location: inflight.tempFileURL, suggestedFileName: fileName, preferredDirectory: preferredDir)
                DownloadLogger.log(itemId: itemId, "finalized file: \(final.path)")
                if started { preferredDir?.stopAccessingSecurityScopedResource() }
                let dir = final.deletingLastPathComponent()
                let bookmark = try? dir.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                // Cleanup state to prevent future erroneous failure updates
                self.itemIdToWriteQueue.removeValue(forKey: itemId)
                self.itemIdToSpeedMeter.removeValue(forKey: itemId)
                self.itemIdToSegmentReceived.removeValue(forKey: itemId)
                self.itemIdToRetryCounts.removeValue(forKey: itemId)
                self.itemIdToRangeRejectCounts.removeValue(forKey: itemId)
                self.itemIdsWithPartialSegmentData.remove(itemId)
                // Leave itemIdToInflight with isFinalized=true as a guard, or remove it entirely:
                // Removing it avoids extra memory; we keep minimal guard by setting flag above.
                await self.updateItem(itemId) { item in
                    item.status = .completed
                    item.speedBytesPerSec = 0
                    item.etaSeconds = 0
                    item.finalFileName = final.lastPathComponent
                    if let bookmark { item.destinationDirBookmark = bookmark }
                    if let total = item.totalBytes { item.receivedBytes = total }
                    if var segs = item.segments {
                        for idx in segs.indices {
                            let need = segs[idx].rangeEnd - segs[idx].rangeStart + 1
                            segs[idx].state = "done"
                            segs[idx].received = need
                        }
                        item.segments = segs
                    }
                }
                // Compute SHA-256 after updating item (non-blocking UI via Task)
                Task {
                    do {
                        let hash = try sha256Hex(of: final)
                        await self.updateItem(itemId) { item in
                            item.checksumSHA256 = hash
                        }
                    } catch {
                        await self.updateItem(itemId) { item in
                            item.lastError = (item.lastError ?? "") + "\nHash error: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                DownloadLogger.log(itemId: itemId, "finalize error: \(error.localizedDescription)")
                // If all segments are complete and file exists at destination, treat as success despite late error
                if FileManager.default.fileExists(atPath: inflight.tempFileURL.path) == false {
                    await self.updateItem(itemId) { item in
                        item.status = .failed
                        item.lastError = error.localizedDescription
                    }
                } else {
                    // Finalizer already moved file or it's present; avoid overriding with failed
                }
            }
        }
    }
}

extension SegmentedSessionManager: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Validate 206 and Content-Range start alignment specifically for data tasks
        if let http = response as? HTTPURLResponse, let itemId = stateQueue.sync(execute: { taskIdToItemId[dataTask.taskIdentifier] }) {
            if let segIndex = stateQueue.sync(execute: { taskIdToSegmentIndex[dataTask.taskIdentifier] }), let inflight = itemIdToInflight[itemId] {
                let expectedStart = stateQueue.sync(execute: { taskIdToExpectedStart[dataTask.taskIdentifier] }) ?? inflight.segments.first(where: { $0.index == segIndex })?.rangeStart ?? 0
                let status = http.statusCode
                if status != 206 {
                    // Special handling: If server returns 200 when we requested a range, it likely means
                    // the download link has expired or the server no longer honors range requests.
                    // This is common with MediaFire and other file hosts with time-limited URLs.
                    if status == 200 && expectedStart > 0 {
                        DownloadLogger.log(itemId: itemId, "server returned 200 instead of 206 for range request (expected start=\(expectedStart)); link may have expired")
                        dataTask.cancel()
                        completionHandler(.cancel)
                        // Track how many times this segment has been rejected due to 200 responses
                        let rejectCount = (itemIdToRangeRejectCounts[itemId]?[segIndex] ?? 0) + 1
                        itemIdToRangeRejectCounts[itemId]?[segIndex] = rejectCount
                        
                        // After 2 rejections, fail with a helpful error message
                        if rejectCount >= 2 {
                            Task { [weak self] in
                                guard let self else { return }
                                await self.updateItem(itemId) { item in
                                    item.status = .failed
                                    item.lastError = "Download link expired or no longer supports resume. This often happens with MediaFire and similar file hosts. Please restart the download with a fresh link."
                                }
                            }
                        }
                        return
                    }
                    // If googlevideo denies ranged (403), try to refresh URL via yt-dlp once, then restart; otherwise fallback to single
                    if status == 403,
                       let h = (dataTask.originalRequest?.url?.host ?? http.url?.host)?.lowercased(),
                       h.contains("googlevideo.com"),
                       let it = itemIdToInflight[itemId] {
                        DownloadLogger.log(itemId: itemId, "rejecting 403 for googlevideo; attempting yt-dlp refresh")
                        it.tasks.forEach { $0.cancel() }
                        completionHandler(.cancel)
                        Task { [weak self] in
                            guard let self, let coord = self.coordinatorRef else { return }
                            // Avoid repeated refresh attempts
                            if !self.itemIdsYTRefreshAttempted.contains(itemId) {
                                self.itemIdsYTRefreshAttempted.insert(itemId)
                                let refreshed = await self.refreshYouTubeURLIfPossible(itemId: itemId)
                                if refreshed {
                                    if let updated = await coord.getItem(id: itemId) {
                                        DownloadLogger.log(itemId: itemId, "yt-dlp resolved fresh URL; restarting segmented download")
                                        await self.startDownload(for: updated)
                                        return
                                    }
                                }
                            }
                            // Refresh failed or already attempted → fallback to single
                            if let item = await coord.getItem(id: itemId), !self.itemIdsSingleStarted.contains(itemId) {
                                self.itemIdsSingleStarted.insert(itemId)
                                self.itemIdsForcedSingle.insert(itemId)
                                DownloadLogger.log(itemId: itemId, "yt-dlp refresh unavailable/failed; starting single-task download")
                                await self.startSingleDownloadTask(item: item)
                            }
                        }
                        return
                    }
                    DownloadLogger.log(itemId: itemId, "rejecting response: status=\(status) for segment #\(segIndex)")
                    dataTask.cancel()
                    completionHandler(.cancel)
                    return
                }
                let cr = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                let parts = cr.replacingOccurrences(of: "bytes ", with: "").split(separator: "/").first?.split(separator: "-")
                let startStr = parts?.first
                let startVal = startStr.flatMap { Int64($0) } ?? -1
                if startVal != expectedStart {
                    DownloadLogger.log(itemId: itemId, "rejecting response: content-range start=\(startVal) expected=\(expectedStart) seg=#\(segIndex)")
                    // Track range rejection and reset segment progress
                    if itemIdToRangeRejectCounts[itemId] == nil {
                        itemIdToRangeRejectCounts[itemId] = [:]
                    }
                    let rejectCount = (itemIdToRangeRejectCounts[itemId]?[segIndex] ?? 0) + 1
                    itemIdToRangeRejectCounts[itemId]?[segIndex] = rejectCount
                    
                    // Reset segment progress to prevent data corruption
                    DownloadLogger.log(itemId: itemId, "resetting segment #\(segIndex) progress due to range mismatch (reject count: \(rejectCount))")
                    itemIdToSegmentReceived[itemId]?[segIndex] = 0
                    
                    // If too many rejections, fail the download to prevent infinite loops with corrupted data
                    if rejectCount >= maxRangeRejectsPerSegment {
                        DownloadLogger.log(itemId: itemId, "segment #\(segIndex) exceeded max range rejections (\(maxRangeRejectsPerSegment)) → failing download")
                        dataTask.cancel()
                        completionHandler(.cancel)
                        Task { [weak self] in
                            guard let self else { return }
                            await self.updateItem(itemId) { item in
                                item.status = .failed
                                item.lastError = "Server does not properly support resume. Range mismatch after \(rejectCount) attempts on segment \(segIndex)."
                            }
                        }
                        return
                    }
                    
                    dataTask.cancel()
                    completionHandler(.cancel)
                    return
                }
                // Enforce identity encoding to avoid corruption
                let ce = (http.value(forHTTPHeaderField: "Content-Encoding") ?? "").lowercased()
                if !ce.isEmpty && ce != "identity" {
                    DownloadLogger.log(itemId: itemId, "rejecting response: content-encoding=\(ce) seg=#\(segIndex)")
                    dataTask.cancel()
                    completionHandler(.cancel)
                    return
                }
                let endStr = parts?.last
                let endVal = endStr.flatMap { Int64($0) } ?? -1
                DownloadLogger.log(itemId: itemId, "accepted response: seg=#\(segIndex) range=\(startVal)-\(endVal) status=\(status)")
                // Track successful range acceptance
                if var inflight = itemIdToInflight[itemId] {
                    if itemIdToRetryCounts[itemId]?[segIndex] ?? 0 > 0 {
                        // Reset retry count on successful resume
                        itemIdToRetryCounts[itemId]?[segIndex] = 0
                    }
                }
            }
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let itemId = stateQueue.sync(execute: { taskIdToItemId[dataTask.taskIdentifier] }),
              let segIndex = stateQueue.sync(execute: { taskIdToSegmentIndex[dataTask.taskIdentifier] }),
              let inflight = itemIdToInflight[itemId] else { return }
        if inflight.isCanceled { return }
        // If we've already finalized (moved temp file), ignore any late data
        if inflight.isFinalized { return }
        let writeQueue = itemIdToWriteQueue[itemId] ?? DispatchQueue.global(qos: .utility)
        let offsetStart = inflight.segments.first(where: { $0.index == segIndex })?.rangeStart ?? 0
        let segmentLength = (inflight.segments.first(where: { $0.index == segIndex })?.rangeEnd ?? 0) - offsetStart + 1
        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Always compute latest 'already' inside the serialized queue to avoid overlapping writes
                let alreadyNow = self.itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
                let writeOffset = UInt64(offsetStart + alreadyNow)
                // Clamp data to not overrun segment; discard any overrun bytes silently
                let remaining = Int(max(0, segmentLength - alreadyNow))
                let toWriteCount = min(remaining, data.count)
                if toWriteCount > 0 {
                    let handle = try FileHandle(forWritingTo: inflight.tempFileURL)
                    try handle.seek(toOffset: writeOffset)
                    try handle.write(contentsOf: data.prefix(toWriteCount))
                    try handle.close()
                }
                // update counters
                let unclamped = alreadyNow + Int64(toWriteCount)
                let clamped = min(Int64(segmentLength), unclamped)
                self.itemIdToSegmentReceived[itemId]?[segIndex] = clamped
                // Conditional progress logging per segment every ~1 MiB or when finished
                let last = self.itemIdToLastLoggedSegmentReceived[itemId]?[segIndex] ?? -1
                let delta = clamped - last
                let oneMiB: Int64 = 1024 * 1024
                if clamped >= Int64(segmentLength) || delta >= oneMiB || last < 0 {
                    let pct = Double(clamped) / Double(max(1, segmentLength)) * 100.0
                    DownloadLogger.log(itemId: itemId, String(format: "segment #%d progress: %lld/%lld (%.1f%%)", segIndex, clamped, segmentLength, pct))
                    var segMap = self.itemIdToLastLoggedSegmentReceived[itemId] ?? [:]
                    segMap[segIndex] = clamped
                    self.itemIdToLastLoggedSegmentReceived[itemId] = segMap
                }
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateItem(itemId) { item in
                        if var segs = item.segments, let idx = segs.firstIndex(where: { $0.index == segIndex }) {
                            let need = segs[idx].rangeEnd - segs[idx].rangeStart + 1
                            let v = self.itemIdToSegmentReceived[itemId]?[segIndex] ?? segs[idx].received
                            segs[idx].received = min(need, v)
                            // If this chunk finished, flip to done immediately so UI turns green
                            segs[idx].state = (segs[idx].received >= need) ? "done" : "downloading"
                            item.segments = segs
                            // Ensure status reflects active progress after any prior failure/reconnect
                            item.status = .downloading
                            item.lastError = nil
                            let totalReceived = segs.reduce(Int64(0)) { partial, s in
                                let needS = s.rangeEnd - s.rangeStart + 1
                                return partial + min(needS, s.received)
                            }
                            item.receivedBytes = totalReceived
                            let speed = self.itemIdToSpeedMeter[itemId]?.update(totalBytes: totalReceived) ?? 0
                            if speed > 0 || item.speedBytesPerSec == 0 {
                                item.speedBytesPerSec = speed
                            }
                            if let total = item.totalBytes, total > 0, item.speedBytesPerSec > 0 {
                                let remaining = Double(total - totalReceived)
                                item.etaSeconds = max(0, remaining / max(1e-6, item.speedBytesPerSec))
                            } else {
                                item.etaSeconds = nil
                            }
                        }
                    }
                }
            } catch {
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateItem(itemId) { item in
                        item.status = .failed
                        item.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let itemId = stateQueue.sync(execute: { taskIdToItemId[task.taskIdentifier] }) else { return }
        defer {
            stateQueue.sync {
                taskIdToItemId.removeValue(forKey: task.taskIdentifier)
                taskIdToSegmentIndex.removeValue(forKey: task.taskIdentifier)
                taskIdToExpectedStart.removeValue(forKey: task.taskIdentifier)
            }
        }
        // Single-task download path: there is no inflight segmented state
        guard let inflight = stateQueue.sync(execute: { itemIdToInflight[itemId] }) else {
            if let error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                DownloadLogger.log(itemId: itemId, "single-task error: \(error.localizedDescription)")
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateItem(itemId) { item in
                        if item.status != .completed {
                            item.status = .failed
                            item.lastError = error.localizedDescription
                        }
                    }
                }
            }
            return
        }
        // If file is already finalized, ignore any late completions or errors for this task
        if inflight.isFinalized { return }
        if let error {
            // Ignore cancellations (they frequently occur when pausing/resuming)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            DownloadLogger.log(itemId: itemId, "task error: \(error.localizedDescription)")
            // Retry this segment automatically, continuing from already-received bytes
            if let segIndex = stateQueue.sync(execute: { taskIdToSegmentIndex[task.taskIdentifier] }),
               let seg = inflight.segments.first(where: { $0.index == segIndex }),
               !inflight.isCanceled {
                // If we already received the entire segment, treat this as success despite the error
                let gotNow = itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
                let needNow = seg.rangeEnd - seg.rangeStart + 1
                if gotNow >= needNow {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.updateItem(itemId) { item in
                            if var segs = item.segments, let idx = segs.firstIndex(where: { $0.index == segIndex }) {
                                segs[idx].state = "done"
                                segs[idx].received = needNow
                                item.segments = segs
                                // Clear any transient error and reflect active/complete state via finalizer
                                item.lastError = nil
                            }
                        }
                    }
                    // Attempt finalization; if not all done yet, other segments will continue
                    tryFinalizeIfComplete(itemId: itemId)
                    return
                }
                let got = itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
                let need = seg.rangeEnd - seg.rangeStart + 1
                let remaining = max(0, need - got)
                let current = itemIdToRetryCounts[itemId]?[segIndex] ?? 0
                if remaining > 0, current < maxRetriesPerSegment {
                    itemIdToRetryCounts[itemId]?[segIndex] = current + 1
                    let delaySeconds = min(30.0, pow(2.0, Double(current)))
                    DownloadLogger.log(itemId: itemId, "retrying segment #\(segIndex) in \(String(format: "%.1f", delaySeconds))s (got=\(got), need=\(need))")
                    Task { [weak self] in
                        guard let self else { return }
                        await self.updateItem(itemId) { item in
                            item.status = .reconnecting
                            item.lastError = error.localizedDescription
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                        guard let self else { return }
                        // Skip retry if we've already finalized the file
                        if let state = self.itemIdToInflight[itemId], state.isFinalized { return }
                        guard let url = task.originalRequest?.url else { return }
                        var req = URLRequest(url: url)
                        req.httpMethod = "GET"
                        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                        if let headers = self.itemIdToRequestHeaders[itemId] { for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) } }
                        if let h = req.url?.host?.lowercased(), h.contains("googlevideo.com") {
                            if req.value(forHTTPHeaderField: "Referer") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
                            if req.value(forHTTPHeaderField: "Origin") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
                            if req.value(forHTTPHeaderField: "User-Agent") == nil {
                                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                            }
                        }
                        let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
                        req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                        let retryTask = self.session.dataTask(with: req)
                        self.stateQueue.async { [weak self] in
                            guard let self else { return }
                            self.taskIdToItemId[retryTask.taskIdentifier] = itemId
                            self.taskIdToSegmentIndex[retryTask.taskIdentifier] = seg.index
                            self.taskIdToExpectedStart[retryTask.taskIdentifier] = seg.rangeStart + got
                            if var inflight = self.itemIdToInflight[itemId] {
                                inflight.tasks.append(retryTask)
                                self.itemIdToInflight[itemId] = inflight
                            }
                        }
                        retryTask.resume()
                    }
                    return
                } else {
                    // Exceeded retries; mark as failed
                    DownloadLogger.log(itemId: itemId, "segment #\(segIndex) exceeded retries → failed")
                    // Before failing, check if we've actually completed all bytes; if so, finalize instead
                    tryFinalizeIfComplete(itemId: itemId)
                    Task { [weak self] in
                        guard let self else { return }
                        // If finalization already happened, avoid overriding status to failed
                        if let inflight = self.itemIdToInflight[itemId], inflight.isFinalized {
                            return
                        }
                        await self.updateItem(itemId) { item in
                            item.status = .failed
                            item.lastError = error.localizedDescription
                        }
                    }
                    return
                }
            } else {
                // No segment info; fail the item unless already finalized
                DownloadLogger.log(itemId: itemId, "task completed with error but no segment info: \(error.localizedDescription)")
                Task { [weak self] in
                    guard let self else { return }
                    if let inflight = self.itemIdToInflight[itemId], inflight.isFinalized { return }
                    await self.updateItem(itemId) { item in
                        item.status = .failed
                        item.lastError = error.localizedDescription
                    }
                }
                return
            }
        }
        // mark segment done if fully received
        if let segIndex = stateQueue.sync(execute: { taskIdToSegmentIndex[task.taskIdentifier] }),
           let seg = inflight.segments.first(where: { $0.index == segIndex }) {
            let got = itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
            let need = seg.rangeEnd - seg.rangeStart + 1
            if got >= need {
                Task { [weak self] in
                    guard let self else { return }
                    await self.updateItem(itemId) { item in
                        if var segs = item.segments, let idx = segs.firstIndex(where: { $0.index == segIndex }) {
                            segs[idx].state = "done"
                            segs[idx].received = need
                            item.segments = segs
                        }
                    }
                }
            }
        }
        // If the segment is not fully received, relaunch remaining bytes
        if let segIndex = stateQueue.sync(execute: { taskIdToSegmentIndex[task.taskIdentifier] }),
           let seg = inflight.segments.first(where: { $0.index == segIndex }) {
            let gotRaw = itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
            let need = seg.rangeEnd - seg.rangeStart + 1
            let got = max(0, min(gotRaw, need))
            if got < need && !inflight.isCanceled {
                if let url = task.originalRequest?.url {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    if let headers = itemIdToRequestHeaders[itemId] { for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) } }
                    if let h = req.url?.host?.lowercased(), h.contains("googlevideo.com") {
                        if req.value(forHTTPHeaderField: "Referer") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer") }
                        if req.value(forHTTPHeaderField: "Origin") == nil { req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin") }
                        if req.value(forHTTPHeaderField: "User-Agent") == nil {
                            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                        }
                    }
                    // Ensure we continue from the correct offset for remaining bytes
                    let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
                    req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                let retryTask = session.dataTask(with: req)
                stateQueue.async { [weak self] in
                    guard let self else { return }
                    self.taskIdToItemId[retryTask.taskIdentifier] = itemId
                    self.taskIdToSegmentIndex[retryTask.taskIdentifier] = seg.index
                    self.taskIdToExpectedStart[retryTask.taskIdentifier] = seg.rangeStart + got
                    if var inflight = self.itemIdToInflight[itemId] {
                        inflight.tasks.append(retryTask)
                        self.itemIdToInflight[itemId] = inflight
                    }
                }
                    retryTask.resume()
                }
            }
        }

        // Finalize only when all segments have been fully received (guard against overcounting)
        tryFinalizeIfComplete(itemId: itemId)
    }
}

// Handle URLSessionDownloadTask for single-task downloads (fallback when ranges are not supported)
extension SegmentedSessionManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemId = stateQueue.sync(execute: { taskIdToItemId[downloadTask.taskIdentifier] }) else { return }
        // Determine suggested filename from response or URL
        let filename: String = {
            if let http = downloadTask.response as? HTTPURLResponse,
               let dispo = http.value(forHTTPHeaderField: "Content-Disposition"),
               let name = dispo.split(separator: ";").compactMap({ part -> String? in
                   let s = part.trimmingCharacters(in: .whitespaces)
                   if s.lowercased().hasPrefix("filename=") { return String(s.dropFirst("filename=".count)) }
                   if s.lowercased().hasPrefix("filename*=utf-8''") { return String(s.dropFirst("filename*=utf-8''".count)) }
                   return nil
               }).first { return name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            return downloadTask.originalRequest?.url?.lastPathComponent ?? "download.bin"
        }()
        // Move to preferred directory if present (must move synchronously before returning; temp file is deleted afterwards)
        let coord = self.coordinatorRef
        var preferredDir: URL? = nil
        if coord != nil {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                if let item = await coord?.getItem(id: itemId), let bookmark = item.destinationDirBookmark {
                    var isStale = false
                    if let dir = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        preferredDir = dir
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
        let started = preferredDir?.startAccessingSecurityScopedResource() ?? false
        defer { if started { preferredDir?.stopAccessingSecurityScopedResource() } }
        do {
            let final = try FileMover.move(location: location, suggestedFileName: filename, preferredDirectory: preferredDir)
            DownloadLogger.log(itemId: itemId, "single-task finalized file: \(final.path)")
            Task { [weak self] in
                await self?.updateItem(itemId) { item in
                    item.status = .completed
                    item.finalFileName = final.lastPathComponent
                    if let sz = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? NSNumber)?.int64Value {
                        item.totalBytes = sz
                        item.receivedBytes = sz
                    }
                    item.speedBytesPerSec = 0
                    item.etaSeconds = 0
                }
            }
        } catch {
            DownloadLogger.log(itemId: itemId, "single-task finalize error: \(error.localizedDescription)")
            Task { [weak self] in
                await self?.updateItem(itemId) { item in
                    item.status = .failed
                    item.lastError = error.localizedDescription
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let itemId = stateQueue.sync(execute: { taskIdToItemId[downloadTask.taskIdentifier] }) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task { [weak self] in
            guard let self else { return }
            await self.updateItem(itemId) { item in
                item.status = .downloading
                item.lastError = nil
                item.supportsRanges = false
                item.totalBytes = expected
                item.receivedBytes = totalBytesWritten
                let speed = self.itemIdToSpeedMeter[itemId]?.update(totalBytes: totalBytesWritten) ?? 0
                if speed > 0 || item.speedBytesPerSec == 0 { item.speedBytesPerSec = speed }
                if let total = item.totalBytes, total > 0, item.speedBytesPerSec > 0 {
                    let remaining = Double(total - item.receivedBytes)
                    item.etaSeconds = max(0, remaining / max(1e-6, item.speedBytesPerSec))
                } else {
                    item.etaSeconds = nil
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let itemId = stateQueue.sync(execute: { taskIdToItemId[downloadTask.taskIdentifier] }) else { return }
        Task { [weak self] in
            await self?.updateItem(itemId) { item in
                item.status = .reconnecting
                item.totalBytes = expectedTotalBytes > 0 ? expectedTotalBytes : item.totalBytes
                item.receivedBytes = fileOffset
            }
        }
    }
}

// MARK: - YouTube helpers
extension SegmentedSessionManager {
    /// If this item looks like a YouTube direct link and we have a Referer pointing to youtube.com,
    /// try to resolve a fresh signed URL with yt-dlp and update the item in coordinator.
    fileprivate func refreshYouTubeURLIfPossible(itemId: UUID) async -> Bool {
        guard let coord = coordinatorRef, let current = await coord.getItem(id: itemId) else { return false }
        guard let host = current.url.host?.lowercased(), host.contains("googlevideo.com") else { return false }
        // Use Referer header as the watch URL if present
        let referer = current.requestHeaders?.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value
        let refererURL: URL? = {
            if let r = referer, let u = URL(string: r), (u.host?.contains("youtube.com") ?? false) { return u }
            return nil
        }()
        guard let watchURL = refererURL else { return false }
        // Pass through headers when resolving to preserve geo/session if needed
        let fresh = YTDLPResolver.resolveDirectURL(for: watchURL, headers: current.requestHeaders, itag: nil)
        guard let freshURL = fresh else { return false }
        await updateItem(itemId) { item in
            item.url = freshURL
            item.totalBytes = nil
            item.receivedBytes = 0
            item.segments = nil
            item.supportsRanges = false
            item.status = .queued
            item.lastError = nil
        }
        return true
    }
}

