import Foundation

public protocol DownloadsPersisting {
    func load() async throws -> [DownloadItem]
    func save(items: [DownloadItem]) async throws
}

public final class JSONDownloadsStore: DownloadsPersisting {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("IDMMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("downloads.json", isDirectory: false)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func load() async throws -> [DownloadItem] {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([DownloadItem].self, from: data)
    }

    public func save(items: [DownloadItem]) async throws {
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
    }
}


