// swift-tools-version: 6.2
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
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "c79c4106b954f81205113c3343e5a7e59a1089b5", traits: [])
    ],
    targets: [
        .binaryTarget(name: "llama", path: ".agent-local/native-llm/llama.xcframework"),
        .target(name: "LocalMinutesCore", path: "Core"),
        .target(name: "LocalMinutesRecording", dependencies: ["LocalMinutesCore"], path: "Recording"),
        .target(name: "LocalMinutesModels", dependencies: ["LocalMinutesCore"], path: "Models",
                resources: [.process("Resources")]),
        .target(name: "LocalMinutesPersistence", dependencies: ["LocalMinutesCore", "LocalMinutesModels"], path: "Persistence", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "LocalMinutesTranscription", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio"),
            "LocalMinutesCore", "LocalMinutesRecording", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesMeetingLibrary"
        ], path: "Transcription", linkerSettings: [.linkedFramework("Accelerate")]),
        .target(name: "LocalMinutesMeetingLibrary", dependencies: ["LocalMinutesCore", "LocalMinutesPersistence", "LocalMinutesRecording"], path: "MeetingLibrary"),
        .target(name: "LocalMinutesSummary", dependencies: ["llama", "LocalMinutesModels", "LocalMinutesPersistence"], path: "Summaries",
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("Metal")]),
        .target(name: "LocalMinutesQuestionAnswering", dependencies: ["LocalMinutesPersistence", "LocalMinutesSummary", "LocalMinutesModels"], path: "QuestionAnswering"),
        .target(name: "LocalMinutesIntelligence", dependencies: ["LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesSummary", "LocalMinutesQuestionAnswering"], path: "Intelligence"),
        .testTarget(name: "CoreTests", dependencies: ["LocalMinutesCore"], path: "Tests/CoreTests", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "RecordingTests", dependencies: ["LocalMinutesRecording", "LocalMinutesCore", "LocalMinutesMeetingLibrary"], path: "Tests/RecordingTests"),
        .testTarget(name: "ModelTests", dependencies: ["LocalMinutesModels", "LocalMinutesCore"], path: "Tests/ModelTests"),
        .testTarget(name: "PersistenceTests", dependencies: ["LocalMinutesPersistence"], path: "Tests/PersistenceTests", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ASRTests", dependencies: ["LocalMinutesTranscription", "LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesRecording", "LocalMinutesMeetingLibrary"], path: "Tests/ASRTests"),
        .testTarget(name: "MeetingLibraryTests", dependencies: ["LocalMinutesMeetingLibrary", "LocalMinutesPersistence", "LocalMinutesRecording", "LocalMinutesModels", "LocalMinutesCore"], path: "Tests/MeetingLibraryTests"),
        .testTarget(name: "SummaryTests", dependencies: ["LocalMinutesSummary", "LocalMinutesModels", "LocalMinutesPersistence", "llama"], path: "Tests/SummaryTests"),
        .testTarget(name: "QuestionAnsweringTests", dependencies: ["LocalMinutesQuestionAnswering", "LocalMinutesPersistence", "LocalMinutesSummary"], path: "Tests/QuestionAnsweringTests"),
        .testTarget(name: "IntelligenceTests", dependencies: ["LocalMinutesIntelligence", "LocalMinutesCore", "LocalMinutesModels", "LocalMinutesPersistence", "LocalMinutesSummary", "LocalMinutesQuestionAnswering"], path: "Tests/IntelligenceTests")
    ]
)
