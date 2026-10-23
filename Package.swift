// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMinutes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LocalMinutesCore", targets: ["LocalMinutesCore"]),
        .library(name: "LocalMinutesRecording", targets: ["LocalMinutesRecording"]),
        .library(name: "LocalMinutesModels", targets: ["LocalMinutesModels"]),
        .library(name: "LocalMinutesPersistence", targets: ["LocalMinutesPersistence"]),
        .library(name: "LocalMinutesTranscription", targets: ["LocalMinutesTranscription"])
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx",
                 revision: "11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf")
    ],
    targets: [
        .target(name: "LocalMinutesCore", path: "Core"),
        .target(name: "LocalMinutesRecording", dependencies: ["LocalMinutesCore"], path: "Recording"),
        .target(name: "LocalMinutesModels", path: "Models"),
        .target(name: "LocalMinutesPersistence", path: "Persistence", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "LocalMinutesTranscription", dependencies: [
            .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            "LocalMinutesRecording", "LocalMinutesModels", "LocalMinutesPersistence"
        ], path: "Transcription"),
        .testTarget(name: "HarnessTests", path: "Tests/HarnessTests"),
        .testTarget(name: "CoreTests", dependencies: ["LocalMinutesCore"], path: "Tests/CoreTests"),
        .testTarget(name: "RecordingTests", dependencies: ["LocalMinutesRecording", "LocalMinutesCore"], path: "Tests/RecordingTests"),
        .testTarget(name: "ModelTests", dependencies: ["LocalMinutesModels"], path: "Tests/ModelTests"),
        .testTarget(name: "PersistenceTests", dependencies: ["LocalMinutesPersistence"], path: "Tests/PersistenceTests", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ASRTests", dependencies: ["LocalMinutesTranscription", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesRecording"], path: "Tests/ASRTests")
    ]
)
