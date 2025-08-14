// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DownloadEngine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DownloadEngine",
            targets: ["DownloadEngine"]
        )
    ],
    targets: [
        .target(
            name: "DownloadEngine",
            path: "Sources"
        ),
        .testTarget(
            name: "DownloadEngineTests",
            dependencies: ["DownloadEngine"],
            path: "Tests"
        )
    ]
)


