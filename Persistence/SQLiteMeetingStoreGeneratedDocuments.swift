import Foundation

/// Initial test-first no-op seams only. See README before activation: these
/// extension stubs cannot access SQLiteMeetingStore's private connection.
/// After actual RED, implementation belongs inside the actor's existing file.
extension SQLiteMeetingStore {
    public func createGeneratedDocument(_ document: StoredGeneratedDocument) throws { }

    public func generatedDocument(id: UUID, meetingID: UUID) throws -> StoredGeneratedDocument? { nil }

    public func generatedDocuments(meetingID: UUID, kind: GeneratedDocumentKind? = nil,
                                   limit: Int = 50) throws -> [StoredGeneratedDocument] { [] }

    public func saveGeneratedDocumentEdit(id: UUID, meetingID: UUID, text: String,
                                          expectedRevision: Int64, modifiedAt: Date) throws -> StoredGeneratedDocument {
        throw GeneratedDocumentStoreError.notFound
    }
}
