import Foundation

public enum YTDLPResolver {
    /// Try to locate a yt-dlp binary on the system PATH or common install locations
    public static func findBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let p = "\(dir)/yt-dlp"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// Resolve a fresh direct media URL for a YouTube watch page using yt-dlp.
    /// - Parameters:
    ///   - pageURL: The YouTube watch page URL (must include video id)
    ///   - headers: Optional HTTP headers to pass through to yt-dlp as --add-header (e.g., cookies)
    ///   - itag: Optional itag to select a specific format. If nil, selects "best".
    /// - Returns: A direct media URL (e.g., googlevideo) if successful, otherwise nil.
    public static func resolveDirectURL(for pageURL: URL, headers: [String: String]?, itag: Int? = nil) -> URL? {
        guard let bin = findBinary() else { return nil }
        var args: [String] = ["-g"]
        if let itag { args += ["-f", "itag==\(itag)"] } else { args += ["-f", "best"] }
        // Prepend headers (yt-dlp expects them before the URL argument)
        if let headers, !headers.isEmpty {
            for (k, v) in headers {
                args.insert(contentsOf: ["--add-header", "\(k): \(v)"] , at: 0)
            }
        }
        args.append(pageURL.absoluteString)
        do {
            let output = try runProcess(bin: bin, arguments: args)
            // yt-dlp -g may output multiple lines (video+audio); pick the first non-empty
            let lines = output
                .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
                .map { String($0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if let first = lines.first, let url = URL(string: first) { return url }
        } catch {
            return nil
        }
        return nil
    }

    private static func runProcess(bin: String, arguments: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        _ = try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}


