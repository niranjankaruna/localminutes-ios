import Foundation

/// Shared lifecycle shape only. Each case owns its actual independent native
/// runtime; choosing one never initializes the other engine.
enum WindowedSpeechRecognizer: Sendable {
    case whisper(WhisperSpeechRecognizer)
    case parakeet(CoreMLParakeetRecognizer)

    func load() async throws {
        switch self {
        case .whisper(let value): try await value.load()
        case .parakeet(let value): try await value.load()
        }
    }
    func start(epochID: UUID) async throws {
        switch self {
        case .whisper(let value): try await value.start(epochID: epochID)
        case .parakeet(let value): try await value.start(epochID: epochID)
        }
    }
    func accept(_ samples: [Float], at start: Int64) async throws -> WhisperSpeechUpdate {
        switch self {
        case .whisper(let value): return try await value.accept(samples, at: start)
        case .parakeet(let value): return try await value.accept(samples, at: start)
        }
    }
    func finish() async throws -> WhisperSpeechUpdate {
        switch self {
        case .whisper(let value): return try await value.finish()
        case .parakeet(let value): return try await value.finish()
        }
    }
    func cancel(epochID: UUID) async {
        switch self {
        case .whisper(let value): await value.cancel(epochID: epochID)
        case .parakeet(let value): await value.cancel(epochID: epochID)
        }
    }
    func unload() async {
        switch self {
        case .whisper(let value): await value.unload()
        case .parakeet(let value): await value.unload()
        }
    }
}
