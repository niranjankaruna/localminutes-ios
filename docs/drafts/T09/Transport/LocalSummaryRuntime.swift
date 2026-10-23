import Foundation
import llama

// Actual native module import; test-first no-op runtime until hosted RED.
public enum LocalSummaryRuntimeError: Error, Equatable, Sendable {
    case notImplemented, modelUnavailable, invalidModel, contextUnavailable, generationFailed
}

public actor LocalSummaryRuntime {
    public init(modelURL: URL, contextSize: UInt32 = 2_048, threads: Int32 = 4) throws {
        throw LocalSummaryRuntimeError.notImplemented
    }

    public func generateJSON(prompt: String, maximumTokens: Int = 192) async throws -> String {
        throw LocalSummaryRuntimeError.notImplemented
    }
}
