import Foundation

public enum DownloadStatus: String, Codable, Hashable {
    case queued, fetchingMetadata, downloading, paused, reconnecting, completed, failed, canceled, deleted
}

public struct Segment: Codable, Hashable {
    public var index: Int
    public var rangeStart: Int64
    public var rangeEnd: Int64 // inclusive
    public var received: Int64
    public var state: String // queued/downloading/paused/done

    public init(index: Int, rangeStart: Int64, rangeEnd: Int64, received: Int64, state: String) {
        self.index = index
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.received = received
        self.state = state
    }
}

public struct DownloadItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var url: URL
    public var finalFileName: String?
    public var destinationDirBookmark: Data?
    public var status: DownloadStatus
    public var totalBytes: Int64?
    public var receivedBytes: Int64
    public var speedBytesPerSec: Double
    public var etaSeconds: Double?
    public var supportsRanges: Bool
    public var checksumSHA256: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var segments: [Segment]?
    public var priority: Int
    public var lastError: String?
    public var previousStatusBeforeDeletion: DownloadStatus?

    public init(
        id: UUID = UUID(),
        url: URL,
        finalFileName: String? = nil,
        destinationDirBookmark: Data? = nil,
        status: DownloadStatus = .queued,
        totalBytes: Int64? = nil,
        receivedBytes: Int64 = 0,
        speedBytesPerSec: Double = 0,
        etaSeconds: Double? = nil,
        supportsRanges: Bool = false,
        checksumSHA256: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        segments: [Segment]? = nil,
        priority: Int = 0,
        lastError: String? = nil,
        previousStatusBeforeDeletion: DownloadStatus? = nil
    ) {
        self.id = id
        self.url = url
        self.finalFileName = finalFileName
        self.destinationDirBookmark = destinationDirBookmark
        self.status = status
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.etaSeconds = etaSeconds
        self.supportsRanges = supportsRanges
        self.checksumSHA256 = checksumSHA256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = segments
        self.priority = priority
        self.lastError = lastError
        self.previousStatusBeforeDeletion = previousStatusBeforeDeletion
    }
}


