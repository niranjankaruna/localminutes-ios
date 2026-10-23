// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMinutes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LocalMinutesCore", targets: ["LocalMinutesCore"]),
        .library(name: "LocalMinutesRecording", targets: ["LocalMinutesRecording"])
    ],
    targets: [
        .target(name: "LocalMinutesCore", path: "Core"),
        .target(name: "LocalMinutesRecording", dependencies: ["LocalMinutesCore"], path: "Recording"),
        .testTarget(name: "HarnessTests", path: "Tests/HarnessTests"),
        .testTarget(name: "CoreTests", dependencies: ["LocalMinutesCore"], path: "Tests/CoreTests"),
        .testTarget(name: "RecordingTests", dependencies: ["LocalMinutesRecording", "LocalMinutesCore"], path: "Tests/RecordingTests")
    ]
)
