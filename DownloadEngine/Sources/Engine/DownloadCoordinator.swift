import Foundation

public actor DownloadCoordinator {
    public static let shared = DownloadCoordinator()

    private var items: [UUID: DownloadItem] = [:]
    private let persistence: any DownloadsPersisting
    private let sessionManager: URLSessionManaging

    public init(
        persistence: any DownloadsPersisting = JSONDownloadsStore(),
        sessionManager: URLSessionManaging? = nil
    ) {
        self.persistence = persistence
        if let sessionManager {
            self.sessionManager = sessionManager
        } else {
            // Use segmented manager by default for speed; fall back to background if desired
            let mgr = SegmentedSessionManager()
            self.sessionManager = mgr
            mgr.setCoordinator(self)
        }
    }

    // MARK: Item lifecycle
    @discardableResult
    public func enqueue(url: URL, suggestedFileName: String? = nil, headers: [String: String]? = nil) async -> DownloadItem {
        return await enqueueWithBookmark(url: url, suggestedFileName: suggestedFileName, headers: headers, bookmark: nil)
    }
    
    @discardableResult
    public func enqueueWithBookmark(url: URL, suggestedFileName: String? = nil, headers: [String: String]? = nil, bookmark: Data? = nil) async -> DownloadItem {
        var item = DownloadItem(url: url, finalFileName: suggestedFileName)
        item.requestHeaders = headers
        item.destinationDirBookmark = bookmark
        // Set status to fetchingMetadata so UI shows "Preparing..." instead of "Queued"
        // This prevents users from clicking resume before startDownload completes
        item.status = .fetchingMetadata
        items[item.id] = item
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
        await sessionManager.startDownload(for: item)
        
        // After startDownload completes, ensure we return the updated item with current status
        // This prevents race conditions where the returned item has stale state
        return items[item.id] ?? item
    }

    public func pause(id: UUID) async {
        guard let item = items[id] else { return }
        await sessionManager.pauseDownload(for: item)
    }

    public func resume(id: UUID) async {
        guard let item = items[id] else { return }
        await sessionManager.resumeDownload(for: item)
    }

    public func cancel(id: UUID) async {
        guard var item = items[id] else { return }
        await sessionManager.cancelDownload(for: item)
        // Eagerly mark as canceled to update UI immediately
        item.status = .canceled
        item.speedBytesPerSec = 0
        items[id] = item
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    }

    public func remove(id: UUID) async {
        items.removeValue(forKey: id)
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    }

    // MARK: - Deletion management
    public func softDelete(id: UUID) async {
        guard var item = items[id] else { return }
        if item.status != .deleted {
            item.previousStatusBeforeDeletion = item.status
            item.status = .deleted
            item.speedBytesPerSec = 0
            item.etaSeconds = nil
            items[id] = item
            await save()
            NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
        }
    }

    public func restore(id: UUID) async {
        guard var item = items[id] else { return }
        guard item.status == .deleted else { return }
        let restoreTo = item.previousStatusBeforeDeletion ?? .paused
        item.status = restoreTo
        item.previousStatusBeforeDeletion = nil
        items[id] = item
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    }

    public func permanentlyDelete(id: UUID) async {
        items.removeValue(forKey: id)
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
    }

    public func allItems() -> [DownloadItem] {
        Array(items.values).sorted { $0.createdAt < $1.createdAt }
    }

    public func getItem(id: UUID) -> DownloadItem? {
        items[id]
    }

    public func handleProgressUpdate(_ updated: DownloadItem) async {
        items[updated.id] = updated
        await save()
        NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
        // Auto-start queued items only when an item completes or fails (not on every progress update)
        if updated.status == .completed || updated.status == .failed || updated.status == .canceled {
            await ensureQueuedStarted()
        }
    }

    // MARK: - Restore persisted items
    public func restoreFromDisk() async {
        do {
            let loaded = try await persistence.load()
            items = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            NotificationCenter.default.post(name: .downloadItemsDidChange, object: nil)
            // Auto-start any queued items from previous session
            await ensureQueuedStarted()
        } catch {
            print("Failed to load downloads: \(error)")
        }
    }

    private func save() async {
        do {
            try await persistence.save(items: Array(items.values))
        } catch {
            // TODO: plug into logging utility later
            print("Failed to save downloads: \(error)")
        }
    }

    // MARK: - Auto start queued items
    private func ensureQueuedStarted() async {
        let queued = items.values.filter { $0.status == .queued }
        guard !queued.isEmpty else { return }
        for q in queued {
            var item = q
            // Mark as preparing to avoid duplicate starts in rapid updates
            item.status = .fetchingMetadata
            items[item.id] = item
            await save()
            await sessionManager.startDownload(for: item)
        }
    }
}


