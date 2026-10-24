import Foundation
import SherpaOnnx
import SherpaOnnxC

public enum ParakeetTDTDecodingMode: Equatable, Sendable { case chunkedOffline }
enum ParakeetTDTNativeOperation: Equatable, Sendable { case load, decode }
typealias ParakeetTDTExecutionObserver = @Sendable (ParakeetTDTNativeOperation, Bool, Bool) -> Void

/// TEST-FIRST INTERFACE ONLY. Parakeet TDT uses sherpa's offline NeMo
/// transducer API. A later implementation must decode bounded, disjoint windows
/// on an owned serial worker; it must never describe this as native streaming.
public actor ParakeetTDTRecognizer {
    public static let sampleRate = 16_000
    public static let stepSamples = 80_000
    public static let maximumWindowSamples = 80_000
    public static let decodingMode: ParakeetTDTDecodingMode = .chunkedOffline

    public init(files: StreamingASRModelFiles) {}
    init(files: StreamingASRModelFiles, executionObserver: @escaping ParakeetTDTExecutionObserver) {}
    public func load() async throws { throw StreamingASRError.notImplemented }
    public func start(epochID: UUID) throws { throw StreamingASRError.notImplemented }
    public func accept(_ samples: [Float], at globalSampleOffset: Int64) async throws -> WhisperSpeechUpdate {
        throw StreamingASRError.notImplemented
    }
    public func finish() async throws -> WhisperSpeechUpdate { throw StreamingASRError.notImplemented }
    public func cancel(epochID: UUID) async {}
    public func unload() async {}
    public func snapshot() -> WhisperSpeechSnapshot {
        .init(phase: .unloaded, epochID: nil, provider: nil, acceptedSampleCount: 0, bufferedSampleCount: 0)
    }
}
