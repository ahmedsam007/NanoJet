import Foundation
import CryptoKit

// Compute SHA-256 for a file at URL and return lowercase hex string
func sha256Hex(of fileURL: URL, chunkSize: Int = 1_048_576) throws -> String {
    var hasher = SHA256()
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }

    while true {
        let data = try handle.read(upToCount: chunkSize) ?? Data()
        if data.isEmpty { break }
        hasher.update(data: data)
    }
    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}


