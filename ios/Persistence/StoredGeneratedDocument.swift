import Foundation
import Synchronization

public enum GeneratedDocumentKind: String, Codable, Equatable, Sendable {
    case summary
    case questionAnswer = "question_answer"
}

/// The original validated generated payload and its provenance remain immutable.
/// Only editedText/editRevision/modifiedAt may change through the edit API.
/// Manual notes and finalized transcripts are independent original records.
public struct StoredGeneratedDocument: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let meetingID: UUID
    public let kind: GeneratedDocumentKind
    public let originalJSON: Data
    public let question: String?
    public let editedText: String
    public let editRevision: Int64
    public let modelRevision: String
    public let promptVersion: String
    public let createdAt: Date
    public let modifiedAt: Date

    public init(id: UUID, meetingID: UUID, kind: GeneratedDocumentKind, originalJSON: Data,
                question: String?, editedText: String, editRevision: Int64 = 0,
                modelRevision: String, promptVersion: String, createdAt: Date, modifiedAt: Date) {
        self.id = id; self.meetingID = meetingID; self.kind = kind; self.originalJSON = originalJSON
        self.question = question; self.editedText = editedText; self.editRevision = editRevision
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }
}

public enum GeneratedDocumentStoreError: Error, Equatable, Sendable {
    case invalidInput, notFound, staleRevision, immutableConflict
}

/// One request's cancellation and SQLite commit admission linearize under one
/// short lock. There is no I/O or suspension while this state is locked.
public final class GeneratedDocumentCommitAdmission: Sendable {
    private enum State: Sendable { case pending, cancelled, accepted }
    private let state = Mutex(State.pending)

    public init() {}

    /// True when cancellation won (including a repeated cancellation). Once
    /// SQLite accepts commit, late cancellation cannot erase its saved result.
    @discardableResult
    public func cancel() -> Bool {
        state.withLock { value in
            if case .accepted = value { return false }
            value = .cancelled
            return true
        }
    }

    public var isCancelled: Bool {
        state.withLock { value in
            if case .cancelled = value { return true }
            return false
        }
    }

    /// SQLite calls this only after acquiring its real write transaction and
    /// before writing the generated row. A cancellation throws into rollback.
    public func acceptCommit() throws {
        try state.withLock { value in
            if case .cancelled = value { throw CancellationError() }
            value = .accepted
        }
    }
}
