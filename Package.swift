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
        .library(name: "LocalMinutesTranscription", targets: ["LocalMinutesTranscription"]),
        .library(name: "LocalMinutesMeetingLibrary", targets: ["LocalMinutesMeetingLibrary"]),
        .library(name: "LocalMinutesSummary", targets: ["LocalMinutesSummary"]),
        .library(name: "LocalMinutesQuestionAnswering", targets: ["LocalMinutesQuestionAnswering"]),
        .library(name: "LocalMinutesIntelligence", targets: ["LocalMinutesIntelligence"])
    ],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx",
                 revision: "11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf")
    ],
    targets: [
        .binaryTarget(name: "llama", path: ".agent-local/native-llm/llama.xcframework"),
        .binaryTarget(name: "WhisperFramework", path: ".agent-local/whisper-fixtures/whisper.xcframework"),
        .target(name: "LocalMinutesCore", path: "Core"),
        .target(name: "LocalMinutesRecording", dependencies: ["LocalMinutesCore"], path: "Recording"),
        .target(name: "LocalMinutesModels", dependencies: ["LocalMinutesCore"], path: "Models"),
        .target(name: "LocalMinutesPersistence", dependencies: ["LocalMinutesCore"], path: "Persistence", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "LocalMinutesTranscription", dependencies: [
            "WhisperFramework",
            .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            "LocalMinutesCore", "LocalMinutesRecording", "LocalMinutesModels", "LocalMinutesPersistence"
        ], path: "Transcription"),
        .target(name: "LocalMinutesMeetingLibrary", dependencies: ["LocalMinutesCore", "LocalMinutesPersistence", "LocalMinutesRecording"], path: "MeetingLibrary"),
        .target(name: "LocalMinutesSummary", dependencies: ["llama"], path: "Summaries",
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("Metal")]),
        .target(name: "LocalMinutesQuestionAnswering", dependencies: ["LocalMinutesPersistence", "LocalMinutesSummary"], path: "QuestionAnswering"),
        .target(name: "LocalMinutesIntelligence", dependencies: ["LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesSummary", "LocalMinutesQuestionAnswering"], path: "Intelligence"),
        .testTarget(name: "HarnessTests", path: "Tests/HarnessTests"),
        .testTarget(name: "CoreTests", dependencies: ["LocalMinutesCore"], path: "Tests/CoreTests"),
        .testTarget(name: "RecordingTests", dependencies: ["LocalMinutesRecording", "LocalMinutesCore", "LocalMinutesMeetingLibrary"], path: "Tests/RecordingTests"),
        .testTarget(name: "ModelTests", dependencies: ["LocalMinutesModels", "LocalMinutesCore"], path: "Tests/ModelTests"),
        .testTarget(name: "PersistenceTests", dependencies: ["LocalMinutesPersistence"], path: "Tests/PersistenceTests", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ASRTests", dependencies: ["LocalMinutesTranscription", "LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesRecording", "LocalMinutesMeetingLibrary"], path: "Tests/ASRTests"),
        .testTarget(name: "MeetingLibraryTests", dependencies: ["LocalMinutesMeetingLibrary", "LocalMinutesPersistence", "LocalMinutesRecording", "LocalMinutesCore"], path: "Tests/MeetingLibraryTests"),
        .testTarget(name: "SummaryTests", dependencies: ["LocalMinutesSummary", "llama"], path: "Tests/SummaryTests"),
        .testTarget(name: "QuestionAnsweringTests", dependencies: ["LocalMinutesQuestionAnswering", "LocalMinutesPersistence", "LocalMinutesSummary"], path: "Tests/QuestionAnsweringTests"),
        .testTarget(name: "IntelligenceTests", dependencies: ["LocalMinutesIntelligence", "LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesSummary", "LocalMinutesQuestionAnswering"], path: "Tests/IntelligenceTests")
    ]
)
