import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// Shared contract for both meeting summaries and questions. The application
/// supplies evidence and a schema; each adapter owns model-specific prompting,
/// native token accounting, generation and teardown.
public protocol SummaryModelRuntime: Sendable {
    func promptTokenCount(prompt: String) async throws -> Int
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                      progress: SummaryGenerationProgressReporter?) async throws -> String
    func unload() async
}

extension SummaryModelRuntime {
    /// Runtimes without native work counters still support the same contract.
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
}

/// The composition boundary is the only place that selects a model adapter.
/// New adapters are registered here without changing summary or Q&A workflows.
public enum SummaryAdapterRegistry {
    public static func configuration(for manifest: ModelManifest) throws -> SummaryModelConfiguration? {
        guard manifest.purpose == .summary, manifest.parakeetConfiguration == nil else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        if let configuration = manifest.summaryConfiguration {
            guard configuration.isSupported, manifest.runtimeVersion == SummaryModelConfiguration.runtimeVersion else {
                throw LocalSummaryRuntimeError.invalidModel
            }
            return configuration
        }
        // Previously installed Qwen 2.5/Phi-3 models keep their original
        // immutable manifests. Actual GGUF metadata determines the legacy path.
        guard manifest.runtimeVersion == "llama.cpp-b5046" else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        return nil
    }

    public static func makeRuntime(modelURL: URL, configuration: SummaryModelConfiguration?) throws -> any SummaryModelRuntime {
        guard let configuration else {
            let engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, threads: 4, chatFormat: .automatic)
            switch engine.chatFormat {
            case .qwen: return Qwen25SummaryAdapter(engine: engine)
            case .phi3: return Phi3SummaryAdapter(engine: engine)
            default: throw LocalSummaryRuntimeError.invalidModel
            }
        }
        guard configuration.isSupported else { throw LocalSummaryRuntimeError.invalidModel }
        switch configuration.family {
        case .qwen25: return try Qwen25SummaryAdapter(modelURL: modelURL)
        case .qwen3: return try Qwen3SummaryAdapter(modelURL: modelURL, variant: configuration.variant)
        case .phi3: return try Phi3SummaryAdapter(modelURL: modelURL)
        case .phi4: return try Phi4SummaryAdapter(modelURL: modelURL)
        case .gemma3: return try Gemma3SummaryAdapter(modelURL: modelURL)
        case .gemma4: return try Gemma4SummaryAdapter(modelURL: modelURL)
        }
    }
}

public struct Qwen25SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    init(engine: LocalSummaryRuntime) { self.engine = engine }
    public init(modelURL: URL) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, chatFormat: .qwen)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}

public struct Qwen3SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    public init(modelURL: URL, variant: SummaryModelVariant = .standard) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096,
            chatFormat: variant == .qwen3Instruct2507 ? .qwen3Instruct2507 : .qwen3)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}

public struct Phi3SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    init(engine: LocalSummaryRuntime) { self.engine = engine }
    public init(modelURL: URL) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, chatFormat: .phi3)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}

/// Phi-4 Mini uses the phi3 tensor architecture, but a distinct no-newline
/// template. It is not the larger Phi-4 model's ChatML/IM_SEP format.
public struct Phi4SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    public init(modelURL: URL) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, chatFormat: .phi4Mini)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}

public struct Gemma3SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    public init(modelURL: URL) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, chatFormat: .gemma3)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}

public struct Gemma4SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    public init(modelURL: URL) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, chatFormat: .gemma4)
    }
    public func promptTokenCount(prompt: String) async throws -> Int { try await engine.promptTokenCount(prompt: prompt) }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    public func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                             progress: SummaryGenerationProgressReporter?) async throws -> String {
        try await engine.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens, progress: progress)
    }
    public func unload() async { await engine.unload() }
}
