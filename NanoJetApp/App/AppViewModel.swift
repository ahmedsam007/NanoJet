import Foundation
import Combine
import AppKit
import Network
import DownloadEngine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var diagnosticsReport: TestReport?
    @Published var shutdownWhenDone: Bool {
        didSet {
            UserDefaults.standard.set(shutdownWhenDone, forKey: "shutdownWhenDone")
            checkForAutoShutdown()
        }
    }
    @Published var isShutdownCountdownActive: Bool = false
    @Published var shutdownCountdownRemaining: Int = 0
    @Published var shutdownError: String?
    @Published var scheduledStartAt: Date?
    @Published var scheduledStopAt: Date?
    @Published var networkDownloadSpeed: Double = 0.0
    @Published var networkUploadSpeed: Double = 0.0
    private var clipboardTimer: Timer?
    private var reconnectTimer: Timer?
    private var scheduleTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ConnectivityMonitor")
    private var previousStatuses: [UUID: DownloadStatus] = [:]
    private var shutdownArmed: Bool = false
    private var shutdownTimer: Timer?
    private var didJustComplete: Bool = false
    // Track items the user explicitly paused so scheduling/auto-resume does not override
    private var userPausedIds: Set<UUID> = []

    private let coordinator = DownloadCoordinator.shared
    private let speedMonitor = NetworkSpeedMonitor.shared

    init() {
        self.shutdownWhenDone = UserDefaults.standard.bool(forKey: "shutdownWhenDone")
        if let startTs = UserDefaults.standard.object(forKey: "scheduledStartAt") as? TimeInterval {
            self.scheduledStartAt = Date(timeIntervalSince1970: startTs)
        }
        if let stopTs = UserDefaults.standard.object(forKey: "scheduledStopAt") as? TimeInterval {
            self.scheduledStopAt = Date(timeIntervalSince1970: stopTs)
        }
        startClipboardWatcher()
        startConnectivityMonitor()
        startAutoReconnectWatcher()
        startScheduleWatcher()
        startNetworkSpeedMonitoring()
        Task { [weak self] in
            guard let self else { return }
            await coordinator.restoreFromDisk()
            self.items = await coordinator.allItems()
            self.previousStatuses = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, $0.status) })
            // Arm shutdown if requested and there are active downloads
            self.shutdownArmed = self.shutdownWhenDone && self.items.contains { [.downloading, .reconnecting, .queued, .fetchingMetadata].contains($0.status) }
            self.updateDockTileProgress(with: self.items)
        }

        NotificationCenter.default.publisher(for: .downloadItemsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    let newItems = await self.coordinator.allItems()
                    self.handleStatusTransitions(oldItems: self.items, newItems: newItems)
                    self.items = newItems
                    self.checkForAutoShutdown()
                    self.updateDockTileProgress(with: newItems)
                }
            }
            .store(in: &cancellables)
    }

    func enqueue(urlString: String, headers: [String: String]? = nil, extras: [String: Any]? = nil, allowDuplicate: Bool = false, completion: ((Bool, String?) -> Void)? = nil) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.validDownloadURL(from: trimmed) else { return }
        Task {
            // Avoid enqueueing duplicates if same URL is already queued or downloading (unless forced)
            if !allowDuplicate {
                let existing = await coordinator.allItems()
                let isDuplicateActive = existing.contains { item in
                    item.url == url && [.queued, .fetchingMetadata, .downloading, .reconnecting].contains(item.status)
                }
                guard !isDuplicateActive else { return }
            }
            
            // Determine source URL for file hosting services
            var sourceURL: URL? = nil
            if let host = url.host?.lowercased() {
                // For MediaFire direct links, try to get the original page URL from referer
                if host.contains("download") && host.contains("mediafire") {
                    // The direct download URL, use referer as source
                    if let referer = headers?.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value,
                       let refererURL = URL(string: referer),
                       refererURL.host?.lowercased().contains("mediafire.com") == true {
                        sourceURL = refererURL
                    }
                } else if host.contains("mediafire.com") && url.pathComponents.contains("file") {
                    // This is already a MediaFire page URL, use it as source
                    sourceURL = url
                }
            }
            
            // Check if external downloader is enabled
            let useExternalDownloader = UserDefaults.standard.bool(forKey: "useExternalDownloader")
            
            // For YouTube/Telegram pages, try resolving a direct media URL via yt-dlp first (if enabled)
            let host = url.host?.lowercased() ?? ""
            if useExternalDownloader && (host.contains("youtube.com") || host.contains("youtu.be") || host.contains("web.telegram.org")) {
                // If a specific itag was requested (from our picker), ask yt-dlp for that itag
                let bookmark = UserDefaults.standard.data(forKey: "downloadDirectoryBookmark")
                if let itag = (extras?["itag"] as? NSNumber)?.intValue ?? (extras?["itag"] as? Int) {
                    if let resolved = await resolveBestURLViaYTDLP(for: url, headers: headers, itag: itag) {
                        DownloadLogger.log(itemId: UUID(), "yt-dlp resolved itag=\(itag): \(resolved.absoluteString)")
                        await coordinator.enqueueWithBookmark(url: resolved, sourceURL: sourceURL ?? url, headers: headers, bookmark: bookmark)
                        self.items = await coordinator.allItems()
                        await MainActor.run { completion?(true, nil) }
                        return
                    }
                }
                if let resolved = await resolveBestURLViaYTDLP(for: url, headers: headers) {
                    DownloadLogger.log(itemId: UUID(), "yt-dlp resolved: \(resolved.absoluteString)")
                    await coordinator.enqueueWithBookmark(url: resolved, sourceURL: sourceURL ?? url, headers: headers, bookmark: bookmark)
                    self.items = await coordinator.allItems()
                    return
                }
                // If yt-dlp failed, fallback to the direct target URL provided by the extension (if any)
                if let targetStr = extras?["target"] as? String, let targetURL = URL(string: targetStr) {
                    DownloadLogger.log(itemId: UUID(), "yt-dlp failed; using extension-provided target URL: \(targetURL.absoluteString)")
                    await coordinator.enqueueWithBookmark(url: targetURL, sourceURL: sourceURL ?? url, headers: headers, bookmark: bookmark)
                    self.items = await coordinator.allItems()
                    return
                }
                // Finally, try resolving again without headers to get a public signed URL from yt-dlp
                if let resolvedNoHdr = await resolveBestURLViaYTDLP(for: url, headers: nil) {
                    DownloadLogger.log(itemId: UUID(), "yt-dlp resolved (no-headers): \(resolvedNoHdr.absoluteString)")
                    await coordinator.enqueueWithBookmark(url: resolvedNoHdr, sourceURL: sourceURL ?? url, headers: headers, bookmark: bookmark)
                    self.items = await coordinator.allItems()
                    return
                }
                // yt-dlp failed - gather a detailed error message and provide helpful guidance
                DownloadLogger.log(itemId: UUID(), "yt-dlp failed to resolve and no target provided; not enqueueing page URL: \(url.absoluteString)")
                let ytdlpInstalled = findYTDLPBinary() != nil
                var detailedError: String? = nil
                if ytdlpInstalled {
                    let (_, err) = await resolveBestURLViaYTDLPDetailed(for: url, headers: headers)
                    detailedError = err
                }
                let errorMsg: String = {
                    if !useExternalDownloader {
                        return "External downloader is not enabled. To download from YouTube, enable 'External Downloader' in Settings and install yt-dlp."
                    }
                    if !ytdlpInstalled {
                        return "yt-dlp not found. Please install yt-dlp manually (brew install yt-dlp) and enable 'External Downloader' in Settings."
                    }
                    if let d = detailedError, !d.isEmpty {
                        return "YouTube: \(d)"
                    }
                    return "YouTube: Unable to resolve a downloadable stream. Try updating yt-dlp, or sign in via browser and use the extension so cookies are passed."
                }()
                await MainActor.run { completion?(false, errorMsg) }
                return
            }
            // If we received a direct googlevideo link but we have a YouTube Referer header,
            // attempt to resolve using the Referer watch URL instead (to get a signed stream URL) - if enabled
            if useExternalDownloader && host.contains("googlevideo.com") {
                if let ref = headers?.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?.value,
                   let refURL = URL(string: ref), (refURL.host?.contains("youtube.com") ?? false) {
                    let bookmark = UserDefaults.standard.data(forKey: "downloadDirectoryBookmark")
                    if let itag = (extras?["itag"] as? NSNumber)?.intValue ?? (extras?["itag"] as? Int), let resolved = await resolveBestURLViaYTDLP(for: refURL, headers: headers, itag: itag) {
                        DownloadLogger.log(itemId: UUID(), "yt-dlp resolved from referer itag=\(itag): \(resolved.absoluteString)")
                        await coordinator.enqueueWithBookmark(url: resolved, sourceURL: sourceURL ?? refURL, headers: headers, bookmark: bookmark)
                        self.items = await coordinator.allItems()
                        await MainActor.run { completion?(true, nil) }
                        return
                    }
                    if let resolved = await resolveBestURLViaYTDLP(for: refURL, headers: headers) {
                        DownloadLogger.log(itemId: UUID(), "yt-dlp resolved from referer: \(resolved.absoluteString)")
                        await coordinator.enqueueWithBookmark(url: resolved, sourceURL: sourceURL ?? refURL, headers: headers, bookmark: bookmark)
                        self.items = await coordinator.allItems()
                        await MainActor.run { completion?(true, nil) }
                        return
                    }
                    // If resolving from referer failed, resolve from the watch URL without headers to get a public signed URL
                    if let itag = (extras?["itag"] as? NSNumber)?.intValue ?? (extras?["itag"] as? Int), let resolved2 = await resolveBestURLViaYTDLP(for: refURL, headers: nil, itag: itag) {
                        DownloadLogger.log(itemId: UUID(), "yt-dlp resolved (no-headers) from referer itag=\(itag): \(resolved2.absoluteString)")
                        await coordinator.enqueueWithBookmark(url: resolved2, sourceURL: sourceURL ?? refURL, headers: headers, bookmark: bookmark)
                        self.items = await coordinator.allItems()
                        await MainActor.run { completion?(true, nil) }
                        return
                    }
                    if let resolved2 = await resolveBestURLViaYTDLP(for: refURL, headers: nil) {
                        DownloadLogger.log(itemId: UUID(), "yt-dlp resolved (no-headers) from referer: \(resolved2.absoluteString)")
                        await coordinator.enqueueWithBookmark(url: resolved2, sourceURL: sourceURL ?? refURL, headers: headers, bookmark: bookmark)
                        self.items = await coordinator.allItems()
                        await MainActor.run { completion?(true, nil) }
                        return
                    }
                }
            }
            // Fallback: enqueue the original URL
            // Pass the bookmark upfront to avoid race conditions
            let bookmark = UserDefaults.standard.data(forKey: "downloadDirectoryBookmark")
            await coordinator.enqueueWithBookmark(url: url, sourceURL: sourceURL, headers: headers, bookmark: bookmark)
            self.items = await coordinator.allItems()
            await MainActor.run { completion?(true, nil) }
        }
    }

    // MARK: - yt-dlp integration (best-effort)
    private func resolveBestURLViaYTDLP(for pageURL: URL, headers: [String: String]?, itag: Int? = nil) async -> URL? {
        let (url, _) = await resolveBestURLViaYTDLPDetailed(for: pageURL, headers: headers, itag: itag)
        return url
    }

    // Detailed resolver that also returns a concise stderr-derived error if resolution fails
    private func resolveBestURLViaYTDLPDetailed(for pageURL: URL, headers: [String: String]?, itag: Int? = nil) async -> (URL?, String?) {
        guard let bin = findYTDLPBinary() else { 
            print("❌ yt-dlp binary not found")
            return (nil, "yt-dlp not found") 
        }
        
        var args: [String] = [
            "--ignore-config",         // Ensure user configs don't change behavior
            "--no-playlist",           // Do not expand playlists when a watch URL includes list=
            "-g",
            "--no-check-certificate",  // Skip SSL verification
            "--no-warnings",            // Reduce output noise  
            "--quiet",                  // Suppress non-error messages
            "--no-cache-dir",           // Don't use cache (faster cold starts can be slower, but ensures consistency)
            "--socket-timeout", "15"   // Reduce per-socket stall to avoid long hangs
        ]
        if let itag {
            // Allow only progressive itags (contain both audio and video)
            let progressiveItags: Set<Int> = [18, 22, 37, 38, 59, 82, 83, 84, 85]
            if progressiveItags.contains(itag) {
                args += ["-f", "itag==\(itag)"]
            } else {
                print("ℹ️ Requested itag=\(itag) is not progressive; falling back to progressive format selection")
                args += [
                    "-f",
                    "best[acodec!=none][vcodec!=none][protocol^=http][protocol!=m3u8_native][protocol!=m3u8][protocol!=dash][ext!=m3u8]/best[ext=mp4][acodec!=none][vcodec!=none][protocol^=http]/22/18/best[acodec!=none][vcodec!=none]"
                ]
            }
        } else {
            // Prefer a single-file progressive HTTP URL (avoid HLS/DASH manifests)
            // 1) best with both audio+video, HTTP(S), not HLS/DASH; 2) best progressive MP4; 3) common progressive itags; 4) last resort: best with A+V
            args += [
                "-f",
                "best[acodec!=none][vcodec!=none][protocol^=http][protocol!=m3u8_native][protocol!=m3u8][protocol!=dash][ext!=m3u8]/best[ext=mp4][acodec!=none][vcodec!=none][protocol^=http]/22/18/best[acodec!=none][vcodec!=none]"
            ]
        }
        args.append(pageURL.absoluteString)
        if let headers, !headers.isEmpty {
            for (k, v) in headers {
                args.insert(contentsOf: ["--add-header", "\(k): \(v)"], at: 0)
            }
        }
        
        print("🔄 Running yt-dlp: \(bin) \(args.joined(separator: " "))")
        
        // Run yt-dlp on a background task to avoid blocking
        do {
            let result = try await runProcess(bin: bin, arguments: args)
            print("📊 yt-dlp exit status: \(result.status)")
            
            if result.status == 0 {
                print("📝 yt-dlp output: \(result.out.prefix(500))")
                let lines = result.out
                    .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
                    .map { String($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                func pickNonManifest(from urls: [String]) -> String? {
                    // Prefer direct GoogleVideo videoplayback URLs or obvious file URLs
                    if let direct = urls.first(where: { u in
                        let s = u.lowercased()
                        return s.contains("googlevideo.com/videoplayback") || s.contains("mime=video/mp4") || s.hasSuffix(".mp4")
                    }) { return direct }
                    // Otherwise, pick the first that is not a manifest
                    return urls.first { u in
                        let s = u.lowercased()
                        return !(s.contains(".m3u8") || s.contains("manifest") || s.contains("playlist.m3u8"))
                    }
                }

                if let chosen = pickNonManifest(from: lines), let url = URL(string: chosen) {
                    print("✅ yt-dlp resolved URL: \(url.absoluteString)")
                    return (url, nil)
                }

                // If only manifests were returned, retry once with stricter progressive-only formats
                print("↪️ yt-dlp returned only HLS/DASH manifests; retrying with progressive-only format set...")
                var retryArgs = args
                if let fIdx = retryArgs.firstIndex(of: "-f"), fIdx + 1 < retryArgs.count {
                    retryArgs[fIdx + 1] = "22/18/best[ext=mp4][acodec!=none][vcodec!=none][protocol^=http]/best[protocol^=http][ext!=m3u8]"
                } else {
                    // Should not happen, but ensure -f exists
                    retryArgs.insert(contentsOf: ["-f", "22/18/best[ext=mp4][acodec!=none][vcodec!=none][protocol^=http]/best[protocol^=http][ext!=m3u8]"], at: 0)
                }
                let result2 = try await runProcess(bin: bin, arguments: retryArgs)
                if result2.status == 0 {
                    let lines2 = result2.out
                        .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
                        .map { String($0) }
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if let chosen2 = pickNonManifest(from: lines2), let url2 = URL(string: chosen2) {
                        print("✅ yt-dlp resolved (retry) URL: \(url2.absoluteString)")
                        return (url2, nil)
                    }
                }

                print("⚠️ yt-dlp succeeded but only returned manifests")
                return (nil, "Received only streaming manifest (HLS/DASH). Try a lower quality (itag 22/18) or sign in via extension.")
            } else {
                print("❌ yt-dlp failed with error: \(result.err.prefix(500))")
                return (nil, parseYTDLPErrorMessage(result.err))
            }
        } catch {
            print("❌ yt-dlp process error: \(error.localizedDescription)")
            return (nil, error.localizedDescription)
        }
    }

    private func findYTDLPBinary() -> String? {
        // Use YTDLPManager to find yt-dlp
        return YTDLPManager.shared.getYTDLPPath()
    }

    private func runProcess(bin: String, arguments: [String]) async throws -> (out: String, err: String, status: Int32) {
        let proc = Process()
        
        // Extract Python path from shebang if yt-dlp
        var actualBin = bin
        var actualArgs = arguments
        
        if bin.contains("yt-dlp") {
            // Read shebang to get Python interpreter
            do {
                let content = try String(contentsOfFile: bin, encoding: .utf8)
                if let shebang = content.split(separator: "\n").first, shebang.hasPrefix("#!") {
                    let pythonPath = String(shebang.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    print("📖 Found shebang: \(pythonPath)")
                    
                    if FileManager.default.fileExists(atPath: pythonPath) {
                        print("✅ Python exists at: \(pythonPath)")
                        actualBin = pythonPath
                        actualArgs = [bin] + arguments
                    } else {
                        print("❌ Python NOT found at: \(pythonPath)")
                    }
                }
            } catch {
                print("⚠️ Could not read yt-dlp file: \(error)")
            }
        }
        
        // Run via shell
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        // Escape arguments for shell
        let escapedArgs = actualArgs.map { arg in
            "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
        }.joined(separator: " ")
        
        let shellCommand = "\(actualBin) \(escapedArgs)"
        proc.arguments = ["-c", shellCommand]
        
        // Set environment to help yt-dlp work in sandbox
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"  // Ensure unbuffered output
        env["YTDLP_NO_UPDATE"] = "1"   // Disable auto-update check
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"  // Ensure PATH is set
        proc.environment = env
        
        print("🐚 Shell command: \(shellCommand)")
        
        // Test if basic process execution works
        if bin.contains("yt-dlp") {
            print("🧪 Testing basic process execution with /bin/echo...")
            let testProc = Process()
            testProc.executableURL = URL(fileURLWithPath: "/bin/echo")
            testProc.arguments = ["test"]
            let testOut = Pipe()
            testProc.standardOutput = testOut
            try? testProc.run()
            testProc.waitUntilExit()
            let testData = testOut.fileHandleForReading.readDataToEndOfFile()
            let testResult = String(data: testData, encoding: .utf8) ?? ""
            print("🧪 Test result: '\(testResult.trimmingCharacters(in: .whitespacesAndNewlines))' (status: \(testProc.terminationStatus))")
        }
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe  // Provide stdin to prevent hanging
        
        // Close stdin immediately so yt-dlp doesn't wait for input
        try? inPipe.fileHandleForWriting.close()
        
        print("▶️ Starting process...")
        
        // Use async/await with timeout
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()
            
            // Set up timeout (yt-dlp can take longer). Allow override via UserDefaults: ytdlpTimeoutSec
            let defaultYTDLPTimeout: TimeInterval = 120.0
            let userTimeout = UserDefaults.standard.double(forKey: "ytdlpTimeoutSec")
            let timeoutSec: TimeInterval = (bin.contains("yt-dlp") ? (userTimeout > 0 ? userTimeout : defaultYTDLPTimeout) : 30.0)
            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timeoutTimer.schedule(deadline: .now() + timeoutSec)
            timeoutTimer.setEventHandler {
                resumeLock.lock()
                if !hasResumed {
                    hasResumed = true
                    resumeLock.unlock()
                    print("⏱️ Process timed out after \(Int(timeoutSec)) seconds (PID: \(proc.processIdentifier))")
                    print("⏱️ Process isRunning: \(proc.isRunning)")
                    
                    // Try terminating gracefully first
                    proc.terminate()
                    Thread.sleep(forTimeInterval: 1.0)
                    
                    // If still running, force kill
                    if proc.isRunning {
                        print("💀 Force killing process...")
                        kill(proc.processIdentifier, SIGKILL)
                    }
                    
                    let msg = bin.contains("yt-dlp") ? "yt-dlp timed out after \(Int(timeoutSec)) seconds" : "process timed out after \(Int(timeoutSec)) seconds"
                    continuation.resume(throwing: NSError(domain: "YTDLPError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    resumeLock.unlock()
                }
            }
            timeoutTimer.resume()
            
            // Set up termination handler before starting process
            proc.terminationHandler = { process in
                print("✓ Process terminated with status: \(process.terminationStatus)")
                timeoutTimer.cancel()
                
                resumeLock.lock()
                if !hasResumed {
                    hasResumed = true
                    resumeLock.unlock()
                    
                    // Read output data after process completes
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    print("📏 Output length: \(outData.count) bytes, Error length: \(errData.count) bytes")
                    
                    let result = (
                        String(data: outData, encoding: .utf8) ?? "",
                        String(data: errData, encoding: .utf8) ?? "",
                        process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } else {
                    resumeLock.unlock()
                }
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try proc.run()
                    print("⏳ Process started (PID: \(proc.processIdentifier)), waiting for termination handler...")
                    // Process will call terminationHandler when done
                } catch {
                    timeoutTimer.cancel()
                    resumeLock.lock()
                    if !hasResumed {
                        hasResumed = true
                        resumeLock.unlock()
                        print("❌ Process failed to start: \(error)")
                        continuation.resume(throwing: error)
                    } else {
                        resumeLock.unlock()
                    }
                }
            }
        }
    }

    private func parseYTDLPErrorMessage(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "Unknown error from yt-dlp" }
        let lower = s.lowercased()
        if lower.contains("age") || lower.contains("sign in") || lower.contains("cookies") || lower.contains("consent") {
            return "Age verification or login required. Sign in on YouTube and use the browser extension so cookies are passed."
        }
        if lower.contains("members-only") || lower.contains("member only") {
            return "Members-only content. Download requires membership (sign in and retry via browser extension)."
        }
        if lower.contains("private video") || lower.contains("private") {
            return "Video is private or access-restricted."
        }
        if lower.contains("premiere") || lower.contains("live") {
            return "Live or premiere content may not be downloadable yet."
        }
        if lower.contains("unsupported url") || lower.contains("no video formats") {
            return "Unsupported or no downloadable formats found for this URL."
        }
        if lower.contains("http error 429") || lower.contains("too many requests") {
            return "YouTube rate-limited this device (HTTP 429). Retry later or use your account via the extension."
        }
        if lower.contains("403") {
            return "Access forbidden (HTTP 403). Sign in or try another format."
        }
        // Fallback: surface the first error line succinctly
        if let line = s.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return line.replacingOccurrences(of: "ERROR: ", with: "")
        }
        return s
    }

    private func handleStatusTransitions(oldItems: [DownloadItem], newItems: [DownloadItem]) {
        // Build lookup for previous statuses
        let oldStatusById: [UUID: DownloadStatus] = {
            if !previousStatuses.isEmpty { return previousStatuses }
            return Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0.status) })
        }()
        var updatedStatuses: [UUID: DownloadStatus] = [:]
        var anyCompletedNow = false
        for item in newItems {
            let old = oldStatusById[item.id]
            if item.status == .completed, old != .completed {
                playSuccessSound()
                anyCompletedNow = true
            }
            updatedStatuses[item.id] = item.status
        }
        previousStatuses = updatedStatuses
        didJustComplete = anyCompletedNow
    }

    private func playSuccessSound() {
        // Use a pleasant system sound
        if let sound = NSSound(named: NSSound.Name("Hero")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func addFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            enqueue(urlString: str, allowDuplicate: true)
        }
    }

    func pause(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            // Remember the user's intent so schedule/auto-resume won't restart it
            _ = await MainActor.run { self.userPausedIds.insert(item.id) }
            DownloadLogger.log(itemId: item.id, "user action: pause")
            await coordinator.pause(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func resume(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            _ = await MainActor.run { self.userPausedIds.remove(item.id) }
            DownloadLogger.log(itemId: item.id, "user action: resume")
            await coordinator.resume(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func cancel(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            DownloadLogger.log(itemId: item.id, "user action: cancel")
            await coordinator.cancel(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func delete(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.softDelete(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func restore(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.restore(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func deletePermanently(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.permanentlyDelete(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func retryDownload(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            DownloadLogger.log(itemId: item.id, "user action: retry download - removing old and starting fresh")
            
            // Remove the old completed item first
            await coordinator.remove(id: item.id)
            
            // Enqueue a fresh download with the same URL, headers, and suggested filename
            // Pass the bookmark upfront to avoid race conditions
            await coordinator.enqueueWithBookmark(
                url: item.url,
                sourceURL: item.sourceURL,
                suggestedFileName: item.finalFileName,
                headers: item.requestHeaders,
                bookmark: item.destinationDirBookmark
            )
            
            self.items = await coordinator.allItems()
        }
    }

    func clearHistory() {
        Task { [weak self] in
            guard let self else { return }
            let items = await coordinator.allItems()
            let historical = items.filter { [.completed, .failed, .canceled, .deleted].contains($0.status) }
            for item in historical {
                await coordinator.remove(id: item.id)
            }
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func clearCompleted(selectedIds: Set<UUID> = []) {
        Task { [weak self] in
            guard let self else { return }
            let items = await coordinator.allItems()
            let completedOnly: [DownloadItem]
            
            if selectedIds.isEmpty {
                // No selection - clear all completed items
                completedOnly = items.filter { $0.status == .completed }
            } else {
                // Clear only selected completed items
                completedOnly = items.filter { $0.status == .completed && selectedIds.contains($0.id) }
            }
            
            for item in completedOnly {
                await coordinator.remove(id: item.id)
            }
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    // MARK: - File Utilities
    func openDownloadedFile(item: DownloadItem) {
        let fileName = (item.finalFileName?.isEmpty == false ? item.finalFileName! : item.url.lastPathComponent)
        var started = false
        var dirURL: URL? = nil
        if let bookmark = item.destinationDirBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                started = resolved.startAccessingSecurityScopedResource()
                dirURL = resolved
            }
        }
        let base = dirURL ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let base {
            let fileURL = base.appendingPathComponent(fileName)
            NSWorkspace.shared.open(fileURL)
            if started { base.stopAccessingSecurityScopedResource() }
            return
        }
    }

    func revealDownloadedFile(item: DownloadItem) {
        let fileName = (item.finalFileName?.isEmpty == false ? item.finalFileName! : item.url.lastPathComponent)
        var started = false
        var dirURL: URL? = nil
        if let bookmark = item.destinationDirBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                started = resolved.startAccessingSecurityScopedResource()
                dirURL = resolved
            }
        }
        let base = dirURL ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let base {
            let fileURL = base.appendingPathComponent(fileName)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            if started { base.stopAccessingSecurityScopedResource() }
            return
        }
    }

    private func resolveFileURL(for item: DownloadItem) -> URL? {
        let fileName = (item.finalFileName?.isEmpty == false ? item.finalFileName! : item.url.lastPathComponent)
        if let dirURL = resolveDestinationDirectory(for: item) {
            return dirURL.appendingPathComponent(fileName)
        }
        return nil
    }

    private func resolveDestinationDirectory(for item: DownloadItem) -> URL? {
        if let bookmark = item.destinationDirBookmark {
            var isStale = false
            if let dirURL = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                let started = dirURL.startAccessingSecurityScopedResource()
                defer { if started { dirURL.stopAccessingSecurityScopedResource() } }
                return dirURL
            }
        }
        // Fallback to Downloads directory
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private func startClipboardWatcher() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // No auto-add yet; we could propose add if URL detected
            _ = self
        }
    }

    private func startConnectivityMonitor() {
        connectionStatus = .checking
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                switch path.status {
                case .satisfied:
                    self.connectionStatus = .online
                    // Log online event for active items
                    Task {
                        let items = await self.coordinator.allItems()
                        for it in items where [.downloading, .reconnecting, .queued, .fetchingMetadata].contains(it.status) {
                            DownloadLogger.log(itemId: it.id, "network: online")
                        }
                    }
                    // Attempt to auto-resume any reconnecting items whenever we observe online
                    let items = await self.coordinator.allItems()
                    for item in items where item.status == .reconnecting && !self.userPausedIds.contains(item.id) {
                        await self.coordinator.resume(id: item.id)
                    }
                    self.items = await self.coordinator.allItems()
                case .unsatisfied, .requiresConnection:
                    self.connectionStatus = .offline
                    // Log offline event for active items
                    Task {
                        let items = await self.coordinator.allItems()
                        for it in items where [.downloading, .reconnecting, .queued, .fetchingMetadata].contains(it.status) {
                            DownloadLogger.log(itemId: it.id, "network: offline")
                        }
                    }
                @unknown default:
                    self.connectionStatus = .offline
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func startAutoReconnectWatcher() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let isOnline = await MainActor.run { self.connectionStatus == .online }
                guard isOnline else { return }
                let items = await self.coordinator.allItems()
                let pausedIds = await MainActor.run { self.userPausedIds }
                let reconnecting = items.filter { $0.status == .reconnecting && !pausedIds.contains($0.id) }
                guard !reconnecting.isEmpty else { return }
                for item in reconnecting { await self.coordinator.resume(id: item.id) }
                let updated = await self.coordinator.allItems()
                await MainActor.run { self.items = updated }
            }
        }
        RunLoop.main.add(reconnectTimer!, forMode: .common)
    }

    // MARK: - Scheduling
    private func startScheduleWatcher() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateSchedule()
            }
        }
        if let scheduleTimer { RunLoop.main.add(scheduleTimer, forMode: .common) }
    }

    // MARK: - Network Speed Monitoring
    private func startNetworkSpeedMonitoring() {
        speedMonitor.startMonitoring()
        
        // Observe speed changes and update our published properties
        speedMonitor.$downloadSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] speed in
                self?.networkDownloadSpeed = speed
            }
            .store(in: &cancellables)
        
        speedMonitor.$uploadSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] speed in
                self?.networkUploadSpeed = speed
            }
            .store(in: &cancellables)
    }

    private func evaluateSchedule() {
        guard let start = scheduledStartAt, let stop = scheduledStopAt, stop > start else { return }
        let now = Date()
        if now >= stop {
            // Time window ended → pause active and clear schedule
            Task { [weak self] in
                guard let self else { return }
                let items = await coordinator.allItems()
                for item in items where [.downloading, .reconnecting, .fetchingMetadata, .queued].contains(item.status) {
                    await coordinator.pause(id: item.id)
                }
                let updated = await self.coordinator.allItems()
                await MainActor.run {
                    self.items = updated
                    self.clearSchedule()
                }
            }
        } else if now >= start {
            // Inside window → resume paused/reconnecting items and ensure queued start
            Task { [weak self] in
                guard let self else { return }
                let items = await coordinator.allItems()
                let pausedIds = await MainActor.run { self.userPausedIds }
                for item in items where [.paused, .reconnecting, .failed].contains(item.status) && !pausedIds.contains(item.id) {
                    await coordinator.resume(id: item.id)
                }
                let updated = await self.coordinator.allItems()
                await MainActor.run { self.items = updated }
            }
        }
    }

    func setSchedule(start: Date, stop: Date) {
        guard stop > start else { return }
        scheduledStartAt = start
        scheduledStopAt = stop
        UserDefaults.standard.set(start.timeIntervalSince1970, forKey: "scheduledStartAt")
        UserDefaults.standard.set(stop.timeIntervalSince1970, forKey: "scheduledStopAt")
        startScheduleWatcher()
        evaluateSchedule()
    }

    func clearSchedule() {
        scheduledStartAt = nil
        scheduledStopAt = nil
        UserDefaults.standard.removeObject(forKey: "scheduledStartAt")
        UserDefaults.standard.removeObject(forKey: "scheduledStopAt")
    }

    // MARK: - Auto Shutdown
    private func checkForAutoShutdown() {
        let hasActive = items.contains { [.downloading, .reconnecting, .queued, .fetchingMetadata].contains($0.status) }
        if shutdownWhenDone {
            if hasActive {
                shutdownArmed = true
                // If activity resumed during a countdown, cancel it
                if isShutdownCountdownActive { cancelShutdownCountdown() }
                // Reset completion trigger while work is ongoing
                didJustComplete = false
            } else if shutdownArmed {
                // No active downloads. Only start countdown if a download just completed (not paused/canceled).
                if didJustComplete && !isShutdownCountdownActive { beginShutdownCountdown() }
                // Reset the flag after evaluation
                didJustComplete = false
            }
        } else {
            shutdownArmed = false
            cancelShutdownCountdown()
            didJustComplete = false
        }
    }

    // MARK: - Dock Tile Progress
    private func updateDockTileProgress(with items: [DownloadItem]) {
        // Compute aggregated progress across active downloads
        let active = items.filter { [.downloading, .reconnecting, .queued, .fetchingMetadata, .paused].contains($0.status) }
        guard !active.isEmpty else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let totals = active.compactMap { $0.totalBytes }.filter { $0 > 0 }
        if !totals.isEmpty {
            let totalBytes = totals.reduce(0, +)
            let receivedBytes = active.reduce(Int64(0)) { acc, item in
                let total = item.totalBytes ?? 0
                let received = min(item.receivedBytes, total > 0 ? total : item.receivedBytes)
                return acc + received
            }
            let percent = max(0, min(100, Int((Double(receivedBytes) / Double(max(1, totalBytes))) * 100.0 + 0.5)))
            NSApp.dockTile.badgeLabel = percent >= 100 ? nil : "\(percent)%"
        } else {
            // Fallback: show number of active downloads
            NSApp.dockTile.badgeLabel = "\(active.count)"
        }
        NSApp.dockTile.display()
    }

    private func beginShutdownCountdown() {
        shutdownTimer?.invalidate()
        shutdownCountdownRemaining = 30
        isShutdownCountdownActive = true
        shutdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                if self.shutdownCountdownRemaining > 0 {
                    self.shutdownCountdownRemaining -= 1
                }
                if self.shutdownCountdownRemaining <= 0 {
                    t.invalidate()
                    self.isShutdownCountdownActive = false
                    self.performShutdownNow()
                }
            }
        }
        RunLoop.main.add(shutdownTimer!, forMode: .common)
    }

    func cancelShutdownCountdown() {
        shutdownTimer?.invalidate()
        shutdownTimer = nil
        isShutdownCountdownActive = false
    }

    func shutdownNow() {
        // User pressed the immediate shutdown button
        cancelShutdownCountdown()
        performShutdownNow()
    }

    private func requestShutdown() async -> Bool {
        var lastError: String? = nil
        // 1) Try Finder (usually running)
        let finderScript = "tell application \"Finder\" to shut down"
        let finderResult = await runAppleScriptOnMain(finderScript)
        if finderResult.success { return true }
        lastError = finderResult.error ?? lastError

        // 2) Try System Events (launch if needed)
        await launchSystemEventsIfNeededOnMain()
        let seScript = "tell application \"System Events\" to shut down"
        let seResult = await runAppleScriptOnMain(seScript)
        if seResult.success { return true }
        lastError = seResult.error ?? lastError

        // 3) Try sending the shutdown Apple event directly to loginwindow
        let lwScript = "ignoring application responses\n tell application id \"com.apple.loginwindow\" to «event aevtrsdn»\nend ignoring"
        let lwResult = await runAppleScriptOnMain(lwScript)
        if lwResult.success { return true }
        lastError = lwResult.error ?? lastError

        if let lastError { self.shutdownError = "Unable to request shutdown: \(lastError)" }
        return false
    }

    private func runAppleScript(_ script: String) -> (success: Bool, error: String?) {
        // Prefer sending Apple Events from this app process to surface Automation permissions.
        let inProc = runAppleScriptInProcess(script)
        if inProc.success { return inProc }
        // Fallback to CLI if in-process fails (e.g., compilation error)
        return runAppleScriptViaCLI(script)
    }

    private func runAppleScriptInProcess(_ script: String) -> (success: Bool, error: String?) {
        guard let appleScript = NSAppleScript(source: script) else {
            return (false, "Failed to create AppleScript")
        }
        var errorInfo: NSDictionary? = nil
        _ = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // Extract a useful error message if available
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? errorInfo.description
            return (false, message)
        }
        return (true, nil)
    }

    private func runAppleScriptViaCLI(_ script: String) -> (success: Bool, error: String?) {
        let proc = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            _ = try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 { return (true, nil) }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)
            let outStr = String(data: outData, encoding: .utf8)
            let msg = (errStr?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil }
                ?? (outStr?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil }
                ?? "osascript failed with status \(proc.terminationStatus)"
            return (false, msg)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func runAppleScriptOnMain(_ script: String) async -> (success: Bool, error: String?) {
        return await MainActor.run { [weak self] in
            guard let self else { return (false, "deallocated") }
            return self.runAppleScript(script)
        }
    }

    private func launchSystemEventsIfNeeded() {
        // Attempt to ensure System Events is running
        let bundleIds = ["com.apple.systemevents", "com.apple.SystemEvents"]
        if let bid = bundleIds.first(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            return
        }
        // Fallback: try the well-known path
        let sysEventsURL = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: sysEventsURL, configuration: config, completionHandler: nil)
    }

    private func launchSystemEventsIfNeededOnMain() async {
        await MainActor.run { [weak self] in
            _ = self?.launchSystemEventsIfNeeded()
        }
    }

    private func performShutdownNow() {
        Task {
            // Preflight to trigger Automation prompt for our app (non-destructive)
            _ = await runAppleScriptOnMain("tell application \"System Events\" to count processes")
            let ok = await requestShutdown()
            if !ok {
                self.shutdownError = "Unable to request shutdown. Grant Automation permission for controlling System Events."
            }
        }
    }

    func openAutomationPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestAutomationPermission() {
        // Trigger the Automation consent dialog by sending a harmless Apple Event
        Task { [weak self] in
            guard let self else { return }
            _ = await self.runAppleScriptOnMain("tell application \"System Events\" to count processes")
        }
    }

    // MARK: Connectivity
    enum ConnectionStatus: Equatable {
        case idle
        case checking
        case online
        case offline
    }

    func testConnection() {
        connectionStatus = .checking
        guard let url = URL(string: "https://clients3.google.com/generate_204") else {
            connectionStatus = .offline
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                    self.connectionStatus = .online
                } else {
                    self.connectionStatus = .offline
                }
                // Fire advanced diagnostics in background
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let tester = ConnectionTester()
                        let report = try await tester.run(for: url)
                        await MainActor.run { self.diagnosticsReport = report }
                    } catch {
                        // ignore diagnostics failure
                    }
                }
            } catch {
                self.connectionStatus = .offline
            }
        }
    }

    static func validDownloadURL(from string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        // Default to https if user forgot scheme and provided a host-like string
        if components.scheme == nil {
            let hostCandidate: String? = {
                if let h = components.host, !h.isEmpty { return h }
                return components.path.split(separator: "/").first.map(String.init)
            }()
            if let hostCandidate, hostCandidate.contains(".") {
                components.scheme = "https"
            }
        }
        guard let scheme = components.scheme?.lowercased(), (scheme == "http" || scheme == "https"), components.host != nil, let url = components.url else { return nil }
        return url
    }
}


