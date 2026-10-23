// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMinutes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .testTarget(name: "HarnessTests", path: "Tests/HarnessTests")
    ]
)
