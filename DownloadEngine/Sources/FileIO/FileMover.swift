import Foundation

enum FileMoverError: Error {
    case noDownloadsDirectory
}

public enum FileMover {
    public static func moveToDownloads(location: URL, suggestedFileName: String?) throws -> URL {
        let fm = FileManager.default
        guard let downloadsDir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw FileMoverError.noDownloadsDirectory
        }
        try fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let safeName = (suggestedFileName ?? location.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = uniqueURL(in: downloadsDir, preferredName: safeName.isEmpty ? UUID().uuidString : safeName)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: location, to: dest)
        return dest
    }

    private static func uniqueURL(in dir: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(preferredName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var idx = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(idx)" : "\(base) \(idx).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            idx += 1
        }
    }
}


