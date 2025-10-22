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
        // If destination exists with same size, treat as success without overwriting
        if fm.fileExists(atPath: dest.path) {
            if let srcAttrs = try? fm.attributesOfItem(atPath: location.path),
               let dstAttrs = try? fm.attributesOfItem(atPath: dest.path),
               let srcSize = srcAttrs[.size] as? NSNumber,
               let dstSize = dstAttrs[.size] as? NSNumber,
               srcSize.int64Value == dstSize.int64Value {
                // Clean up temp and return existing
                try? fm.removeItem(at: location)
                return dest
            }
            try? fm.removeItem(at: dest)
        }
        try fm.moveItem(at: location, to: dest)
        return dest
    }

    // New API: move to a user-specified directory if provided, else fallback to Downloads
    public static func move(location: URL, suggestedFileName: String?, preferredDirectory: URL?) throws -> URL {
        let fm = FileManager.default
        let baseDir: URL
        if let preferredDirectory {
            try fm.createDirectory(at: preferredDirectory, withIntermediateDirectories: true)
            baseDir = preferredDirectory
        } else {
            guard let downloadsDir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw FileMoverError.noDownloadsDirectory
            }
            try fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            baseDir = downloadsDir
        }
        let safeName = (suggestedFileName ?? location.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = uniqueURL(in: baseDir, preferredName: safeName.isEmpty ? UUID().uuidString : safeName)
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


