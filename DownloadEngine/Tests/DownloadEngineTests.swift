import XCTest
@testable import DownloadEngine

final class DownloadEngineTests: XCTestCase {
    func testModelsCodable() throws {
        let item = DownloadItem(url: URL(string: "https://example.com/file.bin")!)
        let data = try JSONEncoder().encode(item)
        _ = try JSONDecoder().decode(DownloadItem.self, from: data)
    }
}


