import Foundation

public enum DownloadLogger {
    private static func logsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IDMMac/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func logFileURL(for itemId: UUID) -> URL {
        logsDirectory().appendingPathComponent("\(itemId.uuidString).log", isDirectory: false)
    }

    public static func log(itemId: UUID, _ message: String) {
        let url = logFileURL(for: itemId)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } catch {
                        // best-effort logging
                    }
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}


