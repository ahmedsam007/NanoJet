import Foundation
import UniformTypeIdentifiers

public protocol URLSessionManaging {
    func startDownload(for item: DownloadItem) async
    func pauseDownload(for item: DownloadItem) async
    func resumeDownload(for item: DownloadItem) async
    func cancelDownload(for item: DownloadItem) async
}

public final class BackgroundSessionManager: NSObject, URLSessionManaging {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var taskIdToItemId: [Int: UUID] = [:]
    private var itemIdToSpeedMeter: [UUID: SpeedMeter] = [:]
    private var itemIdToResumeData: [UUID: Data] = [:]
    private weak var coordinatorRef: DownloadCoordinator?

    public func setCoordinator(_ coordinator: DownloadCoordinator) {
        self.coordinatorRef = coordinator
    }

    public func startDownload(for item: DownloadItem) async {
        DownloadLogger.log(itemId: item.id, "startDownload: url=\(item.url)")
        var req = URLRequest(url: item.url)
        req.httpMethod = "GET"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        // YouTube direct links (googlevideo.com) often require Referer=origin and a realistic User-Agent
        if let host = item.url.host?.lowercased(), host.contains("googlevideo.com") {
            if req.value(forHTTPHeaderField: "Referer") == nil {
                // Best-effort referer to YouTube watch page if present in headers; otherwise fallback to https://www.youtube.com
                let ref = item.requestHeaders?.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value ?? "https://www.youtube.com"
                req.setValue(ref, forHTTPHeaderField: "Referer")
            }
            if req.value(forHTTPHeaderField: "User-Agent") == nil {
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            }
        }
        if let headers = item.requestHeaders {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let cookiePresent = headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame })
            let referer = headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value ?? ""
            DownloadLogger.log(itemId: item.id, "using headers: Referer=\(referer.isEmpty ? "<none>" : referer) Cookie=\(cookiePresent ? "present" : "absent")")
        }
        let task = session.downloadTask(with: req)
        taskIdToItemId[task.taskIdentifier] = item.id
        itemIdToSpeedMeter[item.id] = SpeedMeter()
        task.resume()
    }

    public func pauseDownload(for item: DownloadItem) async {
        DownloadLogger.log(itemId: item.id, "pauseDownload")
        // For background tasks, use cancellation with resume data (async API)
        for (tid, iid) in taskIdToItemId where iid == item.id {
            if let task = taskFor(identifier: tid) as? URLSessionDownloadTask {
                let data = await task.cancelByProducingResumeData()
                if let data { itemIdToResumeData[item.id] = data }
                if let coordinator = coordinatorRef, var current = await coordinator.getItem(id: item.id) {
                    current.status = .paused
                    await coordinator.handleProgressUpdate(current)
                }
            }
        }
    }

    public func resumeDownload(for item: DownloadItem) async {
        DownloadLogger.log(itemId: item.id, "resumeDownload")
        if let data = itemIdToResumeData[item.id] {
            let task = session.downloadTask(withResumeData: data)
            taskIdToItemId[task.taskIdentifier] = item.id
            if itemIdToSpeedMeter[item.id] == nil { itemIdToSpeedMeter[item.id] = SpeedMeter() }
            itemIdToResumeData[item.id] = nil
            task.resume()
        } else {
            await startDownload(for: item)
        }
    }

    public func cancelDownload(for item: DownloadItem) async {
        DownloadLogger.log(itemId: item.id, "cancelDownload")
        for (tid, iid) in taskIdToItemId where iid == item.id {
            taskFor(identifier: tid)?.cancel()
        }
    }

    private func taskFor(identifier: Int) -> URLSessionTask? {
        var found: URLSessionTask?
        let semaphore = DispatchSemaphore(value: 0)
        session.getAllTasks { tasks in
            found = tasks.first(where: { $0.taskIdentifier == identifier })
            semaphore.signal()
        }
        semaphore.wait()
        return found
    }
}

extension BackgroundSessionManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let itemId = taskIdToItemId[downloadTask.taskIdentifier] {
            DownloadLogger.log(itemId: itemId, "didFinishDownloadingTo: temp=\(location.path)")
        }
        // Move to user-preferred folder if available, else Downloads
        let fileName = downloadTask.response?.suggestedFilename
        // Resolve preferred directory without prematurely closing security scope
        var preferredDir: URL? = nil
        if let itemId = taskIdToItemId[downloadTask.taskIdentifier] {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                if let coord = self.coordinatorRef, let item = await coord.getItem(id: itemId), let bookmark = item.destinationDirBookmark {
                    var isStale = false
                    if let dir = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                        preferredDir = dir
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
        // Perform move while security scope is active
        let started = preferredDir?.startAccessingSecurityScopedResource() ?? false
        let finalURL = try? FileMover.move(location: location, suggestedFileName: fileName, preferredDirectory: preferredDir)
        if started { preferredDir?.stopAccessingSecurityScopedResource() }
        if let itemId = taskIdToItemId[downloadTask.taskIdentifier] {
            if let finalURL { DownloadLogger.log(itemId: itemId, "movedTo: \(finalURL.path)") } else { DownloadLogger.log(itemId: itemId, "moveFailed") }
        }
        if let itemId = taskIdToItemId[downloadTask.taskIdentifier] {
            Task {
                if let coordinator = coordinatorRef, var item = await coordinator.getItem(id: itemId) {
                    item.status = .completed
                    item.speedBytesPerSec = 0
                    if let finalURL {
                        item.finalFileName = finalURL.lastPathComponent
                        let dir = finalURL.deletingLastPathComponent()
                        let bookmark = try? dir.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        if let bookmark { item.destinationDirBookmark = bookmark }
                        // Compute SHA-256 in background
                        Task { [weak self] in
                            guard let self else { return }
                            do {
                                let hash = try sha256Hex(of: finalURL)
                                if let coord = self.coordinatorRef, var current = await coord.getItem(id: item.id) {
                                    current.checksumSHA256 = hash
                                    await coord.handleProgressUpdate(current)
                                }
                            } catch {
                                if let coord = self.coordinatorRef, var current = await coord.getItem(id: item.id) {
                                    let suffix = "\nHash error: \(error.localizedDescription)"
                                    current.lastError = (current.lastError ?? "") + suffix
                                    await coord.handleProgressUpdate(current)
                                }
                            }
                        }
                    }
                    await coordinator.handleProgressUpdate(item)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let itemId = taskIdToItemId[task.taskIdentifier] {
            Task {
                if let coordinator = self.coordinatorRef, var item = await coordinator.getItem(id: itemId) {
                    // If already completed earlier (e.g. file moved and state saved), do not override
                    if item.status == .completed { await coordinator.handleProgressUpdate(item); return }
                    if let error {
                        DownloadLogger.log(itemId: itemId, "task completed with error: \(error.localizedDescription)")
                        if let urlError = error as? URLError, urlError.code == .cancelled {
                            // Distinguish user pause vs cancel. If paused, keep paused. Otherwise mark as canceled.
                            if item.status != .paused {
                                item.status = .canceled
                            }
                            item.lastError = nil
                        } else if let urlError = error as? URLError,
                                  [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(urlError.code) {
                            // Transient connectivity errors → show reconnecting
                            item.status = .reconnecting
                            item.lastError = urlError.localizedDescription
                            DownloadLogger.log(itemId: itemId, "reconnecting due to network error: \(urlError.code.rawValue)")
                        } else {
                            item.status = .failed
                            item.lastError = error.localizedDescription
                        }
                    }
                    await coordinator.handleProgressUpdate(item)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let itemId = taskIdToItemId[downloadTask.taskIdentifier] else { return }
        let speed = itemIdToSpeedMeter[itemId]?.update(totalBytes: totalBytesWritten) ?? 0
        Task {
            if let coordinator = self.coordinatorRef, var item = await coordinator.getItem(id: itemId) {
                // We are receiving bytes now; switch from reconnecting to downloading
                item.status = .downloading
                // Clamp received to expected when expected is known
                let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
                item.totalBytes = expected
                if let expected { item.receivedBytes = min(expected, totalBytesWritten) } else { item.receivedBytes = totalBytesWritten }
                // Keep showing last speed even if transiently zero
                if speed > 0 || item.speedBytesPerSec == 0 {
                    item.speedBytesPerSec = speed
                }
                if let total = item.totalBytes, total > 0, item.speedBytesPerSec > 0 {
                    let remaining = Double(total - totalBytesWritten)
                    item.etaSeconds = max(0, remaining / max(1e-6, item.speedBytesPerSec))
                } else {
                    item.etaSeconds = nil
                }
                await coordinator.handleProgressUpdate(item)
            }
        }
    }
}


