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
    private var itemIdToWriteQueue: [UUID: DispatchQueue] = [:]
    private var itemIdToSpeedMeter: [UUID: SpeedMeter] = [:]
    private var itemIdToSegmentReceived: [UUID: [Int: Int64]] = [:]
    private var itemIdToRetryCounts: [UUID: [Int: Int]] = [:]
    // Resume data for fallback single-downloads
    private var itemIdToResumeData: [UUID: Data] = [:]
    private let maxRetriesPerSegment: Int = 5
    private weak var coordinatorRef: DownloadCoordinator?

    public func setCoordinator(_ coordinator: DownloadCoordinator) {
        self.coordinatorRef = coordinator
    }

    public func startDownload(for item: DownloadItem) async {
        // Probe for range support and content length
        do {
            let (supportsRanges, totalBytes) = try await probe(url: item.url)
            if !supportsRanges || totalBytes <= 0 {
                // Fallback: single download using downloadTask so we can pause/resume
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
            itemIdToInflight[item.id] = inflight
            itemIdToWriteQueue[item.id] = DispatchQueue(label: "segmented.write.\(item.id)")
            itemIdToSpeedMeter[item.id] = SpeedMeter()
            // Initialize received map from existing segment progress when reusing
            if shouldReuseExisting {
                itemIdToSegmentReceived[item.id] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.received) })
            } else {
                itemIdToSegmentReceived[item.id] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })
            }
            itemIdToRetryCounts[item.id] = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, 0) })

            // Update item state
            await updateItem(item.id) { i in
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
                let alreadyRaw = itemIdToSegmentReceived[item.id]?[seg.index] ?? 0
                let already = max(0, min(alreadyRaw, segmentLength))
                // If this segment is already fully received, skip launching a task
                if already >= segmentLength { continue }
                var req = URLRequest(url: item.url)
                req.httpMethod = "GET"
                req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let start = seg.rangeStart + already
                let range = ByteRange(start: start, end: seg.rangeEnd)
                req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                let task = session.dataTask(with: req)
                taskIdToItemId[task.taskIdentifier] = item.id
                taskIdToSegmentIndex[task.taskIdentifier] = seg.index
                taskIdToExpectedStart[task.taskIdentifier] = start
                itemIdToInflight[item.id]?.tasks.append(task)
                task.resume()
                launchedAnyTask = true
            }
            // If all segments were already complete (e.g., resuming from persisted state), try to finalize now
            if !launchedAnyTask {
                tryFinalizeIfComplete(itemId: item.id)
            }
        } catch {
            await updateItem(item.id) { i in
                i.status = .failed
                i.lastError = error.localizedDescription
            }
        }
    }

    public func pauseDownload(for item: DownloadItem) async {
        if var inflight = itemIdToInflight[item.id] {
            inflight.isCanceled = true
            itemIdToInflight[item.id] = inflight
            inflight.tasks.forEach { $0.cancel() }
            await updateItem(item.id) { i in i.status = .paused }
        } else {
            // Fallback single download: cancel with resume data
            let semaphore = DispatchSemaphore(value: 0)
            session.getAllTasks { tasks in
                let tasksForItem = tasks.filter { self.taskIdToItemId[$0.taskIdentifier] == item.id }
                if tasksForItem.isEmpty { semaphore.signal(); return }
                for t in tasksForItem {
                    if let dlt = t as? URLSessionDownloadTask {
                        dlt.cancel(byProducingResumeData: { data in
                            if let data { self.itemIdToResumeData[item.id] = data }
                            semaphore.signal()
                        })
                    } else {
                        t.cancel()
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
            await updateItem(item.id) { i in i.status = .paused }
        }
    }

    public func resumeDownload(for item: DownloadItem) async {
        // Resume fallback single download if we have resume data
        if let data = itemIdToResumeData[item.id] {
            let task = session.downloadTask(withResumeData: data)
            taskIdToItemId[task.taskIdentifier] = item.id
            itemIdToResumeData[item.id] = nil
            if itemIdToSpeedMeter[item.id] == nil { itemIdToSpeedMeter[item.id] = SpeedMeter() }
            await updateItem(item.id) { i in i.status = .reconnecting }
            task.resume()
            return
        }
        // Resume segmented by re-starting remaining segments (those not "done")
        guard var inflight = itemIdToInflight[item.id] else {
            await startDownload(for: item)
            return
        }
        // Clear canceled flag so new retries/receives proceed
        if inflight.isCanceled {
            inflight.isCanceled = false
            itemIdToInflight[item.id] = inflight
        }
        let remaining: [Segment] = inflight.segments.filter { $0.received < ($0.rangeEnd - $0.rangeStart + 1) }
        // Ensure retry counts map exists for all segments
        if itemIdToRetryCounts[item.id] == nil {
            itemIdToRetryCounts[item.id] = Dictionary(uniqueKeysWithValues: inflight.segments.map { ($0.index, 0) })
        }
        if remaining.isEmpty {
            // All segments already fully received; finalize now
            // Use shared finalization helper to avoid races and failed status overrides
            tryFinalizeIfComplete(itemId: item.id)
            return
        }
        // Show reconnecting until we actually receive bytes
        await updateItem(item.id) { i in i.status = .reconnecting }
        // Relaunch data tasks for remaining segments
        for seg in remaining {
            let totalLen = seg.rangeEnd - seg.rangeStart + 1
            let got = max(0, min(seg.received, totalLen))
            if got >= totalLen { continue }
            var req = URLRequest(url: item.url)
            req.httpMethod = "GET"
            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
            req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
            let task = session.dataTask(with: req)
            taskIdToItemId[task.taskIdentifier] = item.id
            taskIdToSegmentIndex[task.taskIdentifier] = seg.index
            taskIdToExpectedStart[task.taskIdentifier] = seg.rangeStart + got
            itemIdToInflight[item.id]?.tasks.append(task)
            task.resume()
        }
    }

    public func cancelDownload(for item: DownloadItem) async {
        if var inflight = itemIdToInflight[item.id] {
            inflight.isCanceled = true
            itemIdToInflight[item.id] = inflight
            inflight.tasks.forEach { $0.cancel() }
        }
        await updateItem(item.id) { i in i.status = .canceled }
    }

    private func probe(url: URL) async throws -> (Bool, Int64) {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return (false, 0) }
        let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "").lowercased().contains("bytes")
        let lenStr = http.value(forHTTPHeaderField: "Content-Length") ?? "0"
        let total = Int64(lenStr) ?? 0
        if acceptRanges && total > 0 { return (true, total) }
        // Fallback: tiny ranged GET to check 206
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        r.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, rresp) = try await session.data(for: r)
        if let h = rresp as? HTTPURLResponse, h.statusCode == 206 {
            let len = h.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) } ?? total
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
        let task = session.downloadTask(with: item.url)
        taskIdToItemId[task.taskIdentifier] = item.id
        if itemIdToSpeedMeter[item.id] == nil { itemIdToSpeedMeter[item.id] = SpeedMeter() }
        await updateItem(item.id) { i in
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
        inflight.isFinalized = true
        itemIdToInflight[itemId] = inflight
        Task { [weak self] in
            guard let self, let coord = self.coordinatorRef else { return }
            let item = await coord.getItem(id: itemId)
            let suggested = item?.finalFileName
            let fileName = suggested ?? item?.url.lastPathComponent ?? "download.bin"
            do {
                let final = try FileMover.moveToDownloads(location: inflight.tempFileURL, suggestedFileName: fileName)
                let dir = final.deletingLastPathComponent()
                let bookmark = try? dir.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                // Cleanup state to prevent future erroneous failure updates
                self.itemIdToWriteQueue.removeValue(forKey: itemId)
                self.itemIdToSpeedMeter.removeValue(forKey: itemId)
                self.itemIdToSegmentReceived.removeValue(forKey: itemId)
                self.itemIdToRetryCounts.removeValue(forKey: itemId)
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
                await self.updateItem(itemId) { item in
                    item.status = .failed
                    item.lastError = error.localizedDescription
                }
            }
        }
    }
}

extension SegmentedSessionManager: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Validate 206 and Content-Range start alignment specifically for data tasks
        if let http = response as? HTTPURLResponse, let itemId = taskIdToItemId[dataTask.taskIdentifier] {
            if let segIndex = taskIdToSegmentIndex[dataTask.taskIdentifier], let inflight = itemIdToInflight[itemId] {
                let expectedStart = taskIdToExpectedStart[dataTask.taskIdentifier] ?? inflight.segments.first(where: { $0.index == segIndex })?.rangeStart ?? 0
                let status = http.statusCode
                if status != 206 {
                    dataTask.cancel()
                    completionHandler(.cancel)
                    return
                }
                let cr = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                let parts = cr.replacingOccurrences(of: "bytes ", with: "").split(separator: "/").first?.split(separator: "-")
                let startStr = parts?.first
                let startVal = startStr.flatMap { Int64($0) } ?? -1
                if startVal != expectedStart {
                    dataTask.cancel()
                    completionHandler(.cancel)
                    return
                }
            }
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let itemId = taskIdToItemId[dataTask.taskIdentifier],
              let segIndex = taskIdToSegmentIndex[dataTask.taskIdentifier],
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
                let handle = try FileHandle(forWritingTo: inflight.tempFileURL)
                try handle.seek(toOffset: writeOffset)
                // Clamp data to not overrun segment
                let remaining = Int(max(0, segmentLength - alreadyNow))
                let toWriteCount = min(remaining, data.count)
                if toWriteCount > 0 {
                    try handle.write(contentsOf: data.prefix(toWriteCount))
                }
                try handle.close()
                // update counters
                let unclamped = alreadyNow + Int64(toWriteCount)
                let clamped = min(Int64(segmentLength), unclamped)
                self.itemIdToSegmentReceived[itemId]?[segIndex] = clamped
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
        guard let itemId = taskIdToItemId[task.taskIdentifier], let inflight = itemIdToInflight[itemId] else { return }
        defer {
            taskIdToItemId.removeValue(forKey: task.taskIdentifier)
            taskIdToSegmentIndex.removeValue(forKey: task.taskIdentifier)
            taskIdToExpectedStart.removeValue(forKey: task.taskIdentifier)
        }
        // If file is already finalized, ignore any late completions or errors for this task
        if inflight.isFinalized { return }
        if let error {
            // Ignore cancellations (they frequently occur when pausing/resuming)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            // Retry this segment automatically, continuing from already-received bytes
            if let segIndex = taskIdToSegmentIndex[task.taskIdentifier],
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
                        let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
                        req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                        let retryTask = self.session.dataTask(with: req)
                        self.taskIdToItemId[retryTask.taskIdentifier] = itemId
                        self.taskIdToSegmentIndex[retryTask.taskIdentifier] = seg.index
                        self.itemIdToInflight[itemId]?.tasks.append(retryTask)
                        retryTask.resume()
                    }
                    return
                } else {
                    // Exceeded retries; mark as failed
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
        if let segIndex = taskIdToSegmentIndex[task.taskIdentifier],
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
        if let segIndex = taskIdToSegmentIndex[task.taskIdentifier],
           let seg = inflight.segments.first(where: { $0.index == segIndex }) {
            let gotRaw = itemIdToSegmentReceived[itemId]?[segIndex] ?? 0
            let need = seg.rangeEnd - seg.rangeStart + 1
            let got = max(0, min(gotRaw, need))
            if got < need && !inflight.isCanceled {
                if let url = task.originalRequest?.url {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    let range = ByteRange(start: seg.rangeStart + got, end: seg.rangeEnd)
                    req.setValue(range.httpHeaderValue, forHTTPHeaderField: "Range")
                    let retryTask = session.dataTask(with: req)
                    taskIdToItemId[retryTask.taskIdentifier] = itemId
                    taskIdToSegmentIndex[retryTask.taskIdentifier] = seg.index
                    taskIdToExpectedStart[retryTask.taskIdentifier] = seg.rangeStart + got
                    itemIdToInflight[itemId]?.tasks.append(retryTask)
                    retryTask.resume()
                }
            }
        }

        // Finalize only when all segments have been fully received (guard against overcounting)
        tryFinalizeIfComplete(itemId: itemId)
    }
}


