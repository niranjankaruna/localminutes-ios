import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
import LocalMinutesQuestionAnswering
#endif

public protocol IntelligenceRuntime: Sendable {
    func promptTokenCount(prompt: String) async throws -> Int
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String
    func unload() async
}

// Interface conformance only; all inference remains the existing actual actor.
extension LocalSummaryRuntime: IntelligenceRuntime {}

public typealias IntelligenceRuntimeLoader = @Sendable (VerifiedModel) async throws -> any IntelligenceRuntime

public enum IntelligenceOperation: Equatable, Sendable { case summary, question(String) }

public struct IntelligenceRequest: Equatable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let documentID: UUID
    public let operation: IntelligenceOperation
    public let createdAt: Date
    public init(id: UUID = UUID(), meetingID: UUID, documentID: UUID = UUID(),
                operation: IntelligenceOperation, createdAt: Date = Date()) {
        self.id = id; self.meetingID = meetingID; self.documentID = documentID
        self.operation = operation; self.createdAt = createdAt
    }
}

public enum IntelligencePhase: Equatable, Sendable {
    case idle, loading, generating, saving, draining, completed, cancelled, failed
}

public struct IntelligenceSnapshot: Equatable, Sendable {
    public let phase: IntelligencePhase
    public let requestID: UUID?
    public let meetingID: UUID?
    public let document: StoredGeneratedDocument?
    public init(phase: IntelligencePhase, requestID: UUID?, meetingID: UUID?, document: StoredGeneratedDocument?) {
        self.phase = phase; self.requestID = requestID; self.meetingID = meetingID; self.document = document
    }
}

public enum IntelligenceSessionError: Error, Equatable, Sendable {
    case notImplemented, busy, staleRequest, meetingMissing, invalidModel
}

/// INACTIVE TEST-FIRST STUB. The app-services owner must retain this instance
/// and its outer operation independently of view/caller lifetime.
@MainActor
public final class IntelligenceSession {
    private let manifest: ModelManifest
    public init(store: SQLiteMeetingStore, models: ModelInstallationManager, admission: HeavyModelAdmission,
                manifest: ModelManifest,
                runtimeLoader: @escaping IntelligenceRuntimeLoader = { model in
                    try await IntelligenceSession.loadPinnedRuntime(model)
                }) {
        self.manifest = manifest
    }

    /// Future implementation must validate the exact reviewed manifest/runtime,
    /// then construct real LocalSummaryRuntime off MainActor. No working loader
    /// or native construction is supplied before compatible behavioral RED.
    public nonisolated static func loadPinnedRuntime(_ model: VerifiedModel) async throws -> any IntelligenceRuntime {
        try Task.checkCancellation()
        throw IntelligenceSessionError.notImplemented
    }

    public func run(_ request: IntelligenceRequest) async throws -> StoredGeneratedDocument {
        try Task.checkCancellation()
        let kind: GeneratedDocumentKind
        let question: String?
        switch request.operation {
        case .summary: kind = .summary; question = nil
        case .question(let text): kind = .questionAnswer; question = text
        }
        // Empty value only: no model acquisition, inference or persistence.
        return .init(id: request.documentID, meetingID: request.meetingID, kind: kind,
            originalJSON: Data("{}".utf8), question: question, editedText: "",
            modelRevision: manifest.revision, promptVersion: "",
            createdAt: request.createdAt, modifiedAt: request.createdAt)
    }

    public func cancelAndDrain(requestID: UUID) async throws { try Task.checkCancellation() }
    public func snapshot() -> IntelligenceSnapshot {
        .init(phase: .idle, requestID: nil, meetingID: nil, document: nil)
    }
}
