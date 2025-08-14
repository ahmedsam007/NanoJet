import Foundation

// MARK: - Byte range helper used by segmented downloads
public struct ByteRange: CustomStringConvertible {
    public let start: Int64
    public let end: Int64   // inclusive

    public init(start: Int64, end: Int64) {
        precondition(end >= start, "Invalid byte range: end < start")
        self.start = start
        self.end = end
    }

    public var length: Int64 { end - start + 1 }
    public var httpHeaderValue: String { "bytes=\(start)-\(end)" }
    public var description: String { "[\(start)-\(end)]" }
}

// MARK: - Preallocate a zero-filled file of the desired size
@discardableResult
public func preallocateEmptyFile(at url: URL, size: Int64) throws -> FileHandle {
    // Ensure parent directory exists
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    // Create or truncate the file
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(size))
    try handle.synchronize()
    try handle.seek(toOffset: 0)
    return handle
}


