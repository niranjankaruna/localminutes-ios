import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// Shared contract for both meeting summaries and questions. The application
/// supplies evidence and a schema; each adapter owns model-specific prompting,
/// native token accounting, generation and teardown.
public protocol SummaryModelRuntime: Sendable {
    var contextTokenLimit: Int { get }
    var outputTokenLimit: Int { get }
    func promptTokenCount(prompt: String) async throws -> Int
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                      progress: SummaryGenerationProgressReporter?) async throws -> String
    func unload() async
}

extension SummaryModelRuntime {
    public var contextTokenLimit: Int { SummaryContextWindow.legacy.maximumTokens }
    public var outputTokenLimit: Int { SummaryContextWindow.legacy.outputTokenLimit }
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
            return ModelCatalog.summaryConfiguration(for: manifest)
        }
        // Previously installed Qwen 2.5/Phi-3 models keep their original
        // immutable manifests. Actual GGUF metadata determines the legacy path.
        guard manifest.runtimeVersion == "llama.cpp-b5046" else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        return ModelCatalog.summaryConfiguration(for: manifest)
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
        let context = configuration.contextWindow ?? .legacy
        switch configuration.family {
        case .qwen25: return try Qwen25SummaryAdapter(modelURL: modelURL, contextWindow: context)
        case .qwen3: return try Qwen3SummaryAdapter(modelURL: modelURL, variant: configuration.variant, contextWindow: context)
        case .phi3: return try Phi3SummaryAdapter(modelURL: modelURL, contextWindow: context)
        case .phi4: return try Phi4SummaryAdapter(modelURL: modelURL, contextWindow: context)
        case .gemma3: return try Gemma3SummaryAdapter(modelURL: modelURL, contextWindow: context)
        case .gemma4: return try Gemma4SummaryAdapter(modelURL: modelURL, contextWindow: context)
        }
    }
}

public struct Qwen25SummaryAdapter: SummaryModelRuntime {
    private let engine: LocalSummaryRuntime
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    init(engine: LocalSummaryRuntime) { self.engine = engine }
    public init(modelURL: URL, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow, chatFormat: .qwen)
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
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    public init(modelURL: URL, variant: SummaryModelVariant = .standard, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow,
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
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    init(engine: LocalSummaryRuntime) { self.engine = engine }
    public init(modelURL: URL, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow, chatFormat: .phi3)
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
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    public init(modelURL: URL, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow, chatFormat: .phi4Mini)
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
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    public init(modelURL: URL, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow, chatFormat: .gemma3)
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
    public var contextTokenLimit: Int { engine.contextTokenLimit }
    public var outputTokenLimit: Int { engine.outputTokenLimit }
    public init(modelURL: URL, contextWindow: SummaryContextWindow = .legacy) throws {
        engine = try LocalSummaryRuntime(modelURL: modelURL, contextWindow: contextWindow, chatFormat: .gemma4)
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
