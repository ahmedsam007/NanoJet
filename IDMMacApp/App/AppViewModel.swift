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
    private var clipboardTimer: Timer?
    private var reconnectTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "ConnectivityMonitor")
    private var previousStatuses: [UUID: DownloadStatus] = [:]
    private var shutdownArmed: Bool = false
    private var shutdownTimer: Timer?
    private var didJustComplete: Bool = false

    private let coordinator = DownloadCoordinator.shared

    init() {
        self.shutdownWhenDone = UserDefaults.standard.bool(forKey: "shutdownWhenDone")
        startClipboardWatcher()
        startConnectivityMonitor()
        startAutoReconnectWatcher()
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

    func enqueue(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.validDownloadURL(from: trimmed) else { return }
        Task {
            _ = await coordinator.enqueue(url: url)
            self.items = await coordinator.allItems()
        }
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
            enqueue(urlString: str)
        }
    }

    func pause(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.pause(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func resume(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
            await coordinator.resume(id: item.id)
            self.items = await coordinator.allItems()
            self.updateDockTileProgress(with: self.items)
        }
    }

    func cancel(item: DownloadItem) {
        Task { [weak self] in
            guard let self else { return }
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

    // MARK: - File Utilities
    func openDownloadedFile(item: DownloadItem) {
        if let url = resolveFileURL(for: item) {
            NSWorkspace.shared.open(url)
            return
        }
        if let dirURL = resolveDestinationDirectory(for: item) {
            NSWorkspace.shared.open(dirURL)
        }
    }

    func revealDownloadedFile(item: DownloadItem) {
        if let url = resolveFileURL(for: item) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if let dirURL = resolveDestinationDirectory(for: item) {
            NSWorkspace.shared.open(dirURL)
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
                    // Attempt to auto-resume any reconnecting items whenever we observe online
                    let items = await self.coordinator.allItems()
                    for item in items where item.status == .reconnecting {
                        await self.coordinator.resume(id: item.id)
                    }
                    self.items = await self.coordinator.allItems()
                case .unsatisfied, .requiresConnection:
                    self.connectionStatus = .offline
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
                let reconnecting = items.filter { $0.status == .reconnecting }
                guard !reconnecting.isEmpty else { return }
                for item in reconnecting { await self.coordinator.resume(id: item.id) }
                let updated = await self.coordinator.allItems()
                await MainActor.run { self.items = updated }
            }
        }
        RunLoop.main.add(reconnectTimer!, forMode: .common)
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
        let finderResult = runAppleScriptViaCLI(finderScript)
        if finderResult.success { return true }
        lastError = finderResult.error ?? lastError

        // 2) Try System Events (launch if needed)
        await launchSystemEventsIfNeededOnMain()
        let seScript = "tell application \"System Events\" to shut down"
        let seResult = runAppleScriptViaCLI(seScript)
        if seResult.success { return true }
        lastError = seResult.error ?? lastError

        // 3) Try sending the shutdown Apple event directly to loginwindow
        let lwScript = "ignoring application responses\n tell application id \"com.apple.loginwindow\" to «event aevtrsdn»\nend ignoring"
        let lwResult = runAppleScriptViaCLI(lwScript)
        if lwResult.success { return true }
        lastError = lwResult.error ?? lastError

        if let lastError { self.shutdownError = "Unable to request shutdown: \(lastError)" }
        return false
    }

    private func runAppleScript(_ script: String) -> (success: Bool, error: String?) {
        // Use osascript exclusively to avoid in-process AppleScript issues in sandbox
        return runAppleScriptViaCLI(script)
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
            try proc.run()
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


