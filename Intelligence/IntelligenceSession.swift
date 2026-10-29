import Foundation
import CryptoKit
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
import LocalMinutesQuestionAnswering
#endif

/// Source compatibility for existing callers; all adapters share the lower-level
/// summary/Q&A contract, which has no application-session dependencies.
public typealias IntelligenceRuntime = SummaryModelRuntime

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
    case busy, staleRequest, meetingMissing, invalidModel, transcriptMissing
}

private final class IntelligenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

/// App-services owns this session independently of view/caller lifetime. The
/// generation worker and the retained outer cleanup/save operation are distinct.
@MainActor
public final class IntelligenceSession {
    @MainActor
    private final class Use: HeavyModelResourceLifecycle {
        let request: IntelligenceRequest
        let models: ModelInstallationManager
        let progress: IntelligenceProgressReporter?
        let cancellation = GeneratedDocumentCommitAdmission()
        var admissionLease: HeavyModelUseLease?
        var modelLease: ModelLease?
        var runtime: (any IntelligenceRuntime)?
        var work: Task<StoredGeneratedDocument, Error>?
        var completion: Task<StoredGeneratedDocument, Error>?
        var cleanup: Task<Void, Error>?
        var released = false
        var cleanupBlocked = false
        var committed = false

        init(request: IntelligenceRequest, models: ModelInstallationManager, progress: IntelligenceProgressReporter?) {
            self.request = request; self.models = models; self.progress = progress
        }

        func requestCancellation() { work?.cancel() }

        func drain() async throws {
            // Never join completion: it is the outer operation awaiting this
            // gate cleanup. Joining only the worker avoids a cleanup self-join.
            if let work { _ = await work.result }
        }

        func unloadAndReleaseModel() async throws {
            if let runtime { await runtime.unload(); self.runtime = nil }
            if let lease = modelLease { try await models.release(lease); modelLease = nil }
        }
    }

    private let store: SQLiteMeetingStore
    private let models: ModelInstallationManager
    private let admission: HeavyModelAdmission
    // Read-only composition observation; this is the actual stored dependency.
    var heavyAdmissionIdentity: HeavyModelAdmission { admission }
    private let manifest: ModelManifest
    private let runtimeLoader: IntelligenceRuntimeLoader?
    // App-owned progress survives a request/view/session; the stable active
    // summary job belongs to the selected meeting until commit or explicit reset.
    private let summaryCheckpoints: SummaryCheckpointStore?
    private var current: Use?
    private var state = IntelligenceSnapshot(phase: .idle, requestID: nil, meetingID: nil, document: nil)
    public init(store: SQLiteMeetingStore, models: ModelInstallationManager, admission: HeavyModelAdmission,
                manifest: ModelManifest,
                runtimeLoader: IntelligenceRuntimeLoader? = nil, summaryCheckpoints: SummaryCheckpointStore? = nil) {
        self.store = store; self.models = models; self.admission = admission
        self.manifest = manifest; self.runtimeLoader = runtimeLoader
        self.summaryCheckpoints = summaryCheckpoints
    }

    /// Validate the reviewed local artifact, then construct the CPU runtime
    /// explicitly off MainActor. Cancellation joins loading before releasing it.
    public nonisolated static func loadPinnedRuntime(_ model: VerifiedModel,
        progress: IntelligenceProgressReporter? = nil) async throws -> any IntelligenceRuntime {
        try Task.checkCancellation()
        let manifest = model.manifest
        let configuration: SummaryModelConfiguration?
        do { configuration = try SummaryAdapterRegistry.configuration(for: manifest) }
        catch { throw IntelligenceSessionError.invalidModel }
        func lowerHex(_ value: String, count: Int) -> Bool {
            value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        func component(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 255 && value != "." && value != ".."
                && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }
        }
        func publicHF(_ value: URL) -> Bool {
            value.scheme?.lowercased() == "https" && value.host?.lowercased() == "huggingface.co"
                && value.user == nil && value.password == nil && value.port == nil
                && value.query == nil && value.fragment == nil
        }
        guard manifest.schemaVersion == 1, component(manifest.modelID), manifest.purpose == .summary,
              lowerHex(manifest.revision, count: 40),
              !manifest.licenseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.sampleRate == nil, manifest.featureDimension == nil,
              manifest.artifacts.count == 1, let artifact = manifest.artifacts.first,
              artifact.role == .summary, component(artifact.fileName), artifact.byteCount > 0,
              lowerHex(artifact.sha256, count: 64),
              model.directoryURL.isFileURL, model.files.count == 1,
              let file = model.files[.summary], file.isFileURL,
              file.standardizedFileURL.path == model.directoryURL.appendingPathComponent(artifact.fileName).standardizedFileURL.path else {
            throw IntelligenceSessionError.invalidModel
        }
        let source = manifest.upstreamRepository
        let repository = source.path.split(separator: "/")
        let expectedURL = source.appendingPathComponent("resolve").appendingPathComponent(manifest.revision)
            .appendingPathComponent(artifact.fileName)
        guard publicHF(source), repository.count == 2,
              repository.allSatisfy({ $0 != "." && $0 != ".." }), publicHF(artifact.downloadURL),
              artifact.downloadURL.absoluteString == expectedURL.absoluteString,
              model.directoryURL.lastPathComponent == model.installationID.uuidString,
              model.directoryURL.deletingLastPathComponent().lastPathComponent == manifest.revision,
              model.directoryURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == manifest.modelID else {
            throw IntelligenceSessionError.invalidModel
        }
        let digest = artifact.sha256
        let byteCount = artifact.byteCount
        let cancellation = IntelligenceCancellation()
        let loading = Task.detached(priority: .userInitiated) { () throws -> any SummaryModelRuntime in
            try Task.checkCancellation()
            do {
                try PersistentFilePolicy.validateItem(file, within: model.directoryURL)
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      (attributes[.size] as? NSNumber)?.int64Value == byteCount else {
                    throw IntelligenceSessionError.invalidModel
                }
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                var hash = SHA256()
                var readCount: Int64 = 0
                var reportedBytes: Int64 = 0
                progress?(.loadingModel(completedBytes: 0, totalBytes: byteCount))
                try ModelFileIO.forEachChunk(in: input) { bytes in
                    try Task.checkCancellation()
                    if readCount == 0, !bytes.starts(with: [0x47, 0x47, 0x55, 0x46]) {
                        throw IntelligenceSessionError.invalidModel
                    }
                    guard Int64(bytes.count) <= byteCount - readCount else { throw IntelligenceSessionError.invalidModel }
                    readCount += Int64(bytes.count)
                    guard readCount <= byteCount else { throw IntelligenceSessionError.invalidModel }
                    hash.update(data: bytes)
                    // Avoid one MainActor hop for each 64 KB read of a GB model.
                    if readCount - reportedBytes >= 4_194_304 {
                        progress?(.loadingModel(completedBytes: readCount, totalBytes: byteCount))
                        reportedBytes = readCount
                    }
                }
                guard readCount == byteCount,
                      hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else {
                    throw IntelligenceSessionError.invalidModel
                }
                progress?(.loadingModel(completedBytes: readCount, totalBytes: byteCount))
            } catch is CancellationError { throw CancellationError() }
            catch { throw IntelligenceSessionError.invalidModel }
            try Task.checkCancellation()
            // Once native construction begins, always return its actor to the
            // joining owner. A late cancellation must explicitly unload it.
            return try SummaryAdapterRegistry.makeRuntime(modelURL: file, configuration: configuration)
        }
        return try await withTaskCancellationHandler {
            let runtime: any SummaryModelRuntime
            do { runtime = try await loading.value }
            catch {
                if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
                throw error
            }
            if cancellation.isCancelled || Task.isCancelled {
                await runtime.unload()
                throw CancellationError()
            }
            return runtime
        } onCancel: {
            cancellation.cancel()
            loading.cancel()
        }
    }

    public func run(_ request: IntelligenceRequest, progress: IntelligenceProgressReporter? = nil) async throws -> StoredGeneratedDocument {
        try Task.checkCancellation()
        guard current == nil else { throw IntelligenceSessionError.busy }
        let use = Use(request: request, models: models, progress: progress)
        let purpose: HeavyModelPurpose
        switch request.operation { case .summary: purpose = .summary; case .question: purpose = .questionAnswering }
        // Reserve the one shared heavy claim before any model/store suspension.
        use.admissionLease = try admission.acquire(purpose: purpose, requestID: request.id, resource: use)
        current = use
        project(use, phase: .loading)
        let work = Task { @MainActor in try await self.generate(use) }
        use.work = work
        let completion = Task { @MainActor in try await self.complete(use, work: work) }
        use.completion = completion
        let cancellation = use.cancellation
        return try await withTaskCancellationHandler {
            try await completion.value
        } onCancel: {
            if cancellation.cancel() { Task { @MainActor in self.cancelWork(use) } }
        }
    }

    public func cancelAndDrain(requestID: UUID) async throws {
        guard let use = current, use.request.id == requestID else { throw IntelligenceSessionError.staleRequest }
        if use.cancellation.cancel() { cancelWork(use) }
        // A failed native/file-lease cleanup retains current and the gate. Only
        // this later explicit request retries that same resource generation.
        if use.cleanupBlocked {
            do { try await cleanup(use); finish(use, phase: .cancelled) }
            catch { project(use, phase: .failed); throw error }
        } else if let completion = use.completion {
            do { _ = try await completion.value }
            catch is CancellationError { }
            catch { throw error }
        }
        try Task.checkCancellation()
    }

    public func snapshot() -> IntelligenceSnapshot { state }

    private func cancelWork(_ use: Use) {
        guard current === use, !use.committed, use.cancellation.isCancelled else { return }
        use.work?.cancel()
        project(use, phase: .draining)
    }

    private func check(_ use: Use) throws {
        try Task.checkCancellation()
        guard current === use else { throw IntelligenceSessionError.staleRequest }
        if use.cancellation.isCancelled { throw CancellationError() }
        guard let lease = use.admissionLease else { throw IntelligenceSessionError.staleRequest }
        try admission.validate(lease)
    }

    private func generate(_ use: Use) async throws -> StoredGeneratedDocument {
        try check(use)
        use.progress?(.preparing)
        let request = use.request
        guard request.createdAt.timeIntervalSince1970.isFinite else { throw GeneratedDocumentStoreError.invalidInput }
        guard let meeting = try await store.meeting(id: request.meetingID) else { throw IntelligenceSessionError.meetingMissing }
        try check(use)
        guard meeting.recordingState != .recording else { throw IntelligenceSessionError.busy }
        let segments = try await store.transcript(meetingID: request.meetingID)
        try check(use)
        if case .summary = request.operation, segments.isEmpty {
            throw IntelligenceSessionError.transcriptMissing
        }
        let note = try await store.manualNote(meetingID: request.meetingID)
        try check(use)
        let runtime: any IntelligenceRuntime
        let lease = try await models.acquire(modelID: manifest.modelID)
        use.modelLease = lease
        try check(use)
        guard lease.model.manifest == manifest, manifest.purpose == .summary,
              lease.model.files[.summary] != nil else { throw IntelligenceSessionError.invalidModel }
        if let runtimeLoader {
            runtime = try await runtimeLoader(lease.model)
        } else {
            runtime = try await Self.loadPinnedRuntime(lease.model, progress: use.progress)
        }
        let modelRevision = manifest.revision
        use.runtime = runtime
        try check(use)
        project(use, phase: .generating)
        switch request.operation {
        case .summary:
            let source = GroundedSummarySource(meetingID: request.meetingID,
                segments: segments.map { .init(id: $0.id.uuidString, startSample: $0.startSample,
                    endSample: $0.endSample, text: $0.text) }, originalManualNotes: note?.text ?? "")
            let resume: SummaryPipelineResumeConfiguration?
            if let summaryCheckpoints {
                guard let artifact = manifest.artifacts.first(where: { $0.role == .summary }) else {
                    throw IntelligenceSessionError.invalidModel
                }
                // An older installed manifest still describes its original
                // artifact contract. Checkpoints must identify the engine now
                // doing inference so b5046 maps are not reused after upgrading.
                let runtimeVersion = manifest.runtimeVersion == "llama.cpp-b5046"
                    ? SummaryModelConfiguration.runtimeVersion : manifest.runtimeVersion
                resume = .init(jobID: request.meetingID, modelID: manifest.modelID,
                    modelSHA256: artifact.sha256, runtimeVersion: runtimeVersion,
                    checkpoints: summaryCheckpoints)
            } else { resume = nil }
            let report = use.progress
            let pipeline = SummaryPipeline(modelRevision: modelRevision,
                contextTokenLimit: runtime.contextTokenLimit,
                reservedOutputTokens: runtime.outputTokenLimit,
                tokenizer: { try await runtime.promptTokenCount(prompt: $0) },
                generator: { prompt, schema, maximum in
                    report?(.generationStarted)
                    do {
                        return try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum,
                            progress: { report?(.generating($0)) })
                    } catch LocalSummaryRuntimeError.outputLimitExceeded {
                        report?(.recoveringSummary)
                        throw LocalSummaryRuntimeError.outputLimitExceeded
                    }
                }, resume: resume, mapProgress: { completed, total in
                    report?(.summaryChunks(completed: completed, total: total))
                }, consolidationProgress: { completed, total in
                    report?(.consolidatingSummary(completed: completed, total: total))
                }, planningProgress: { completed, total, pass in
                    report?(.planningSummary(completed: completed, total: total, pass: pass))
                })
            let summary = try await pipeline.summarize(selectedMeetingID: request.meetingID, source: source)
            try check(use)
            return try Self.document(summary: summary, request: request, revision: modelRevision)
        case .question(let question):
            use.progress?(.answering)
            let report = use.progress
            let answerer = MeetingQuestionAnswerer(store: store, modelRevision: modelRevision,
                limits: .init(contextTokenLimit: runtime.contextTokenLimit),
                tokenCounter: { try await runtime.promptTokenCount(prompt: $0) },
                generator: { try await runtime.generateJSON(prompt: $0.prompt, schema: $0.schema,
                    maximumTokens: $0.maximumOutputTokens, progress: { report?(.generating($0)) }) })
            let answer = try await answerer.answer(meetingID: request.meetingID, question: question)
            try check(use)
            return try Self.document(answer: answer, request: request)
        }
    }

    private func complete(_ use: Use, work: Task<StoredGeneratedDocument, Error>) async throws -> StoredGeneratedDocument {
        let generated = await work.result
        project(use, phase: .draining)
        do { try await cleanup(use) }
        catch {
            // Preserve the actual resource/gate claim for an explicit retry.
            use.cleanupBlocked = true
            project(use, phase: .failed)
            throw error
        }
        if use.cancellation.isCancelled {
            finish(use, phase: .cancelled)
            throw CancellationError()
        }
        let document: StoredGeneratedDocument
        do { document = try generated.get() }
        catch {
            finish(use, phase: error is CancellationError ? .cancelled : .failed)
            throw error
        }
        project(use, phase: .saving)
        use.progress?(.saving)
        do {
            // This one committed SQLite write is the saved-result boundary.
            // Cancellation after accepted commit cannot erase an editable row.
            try await store.createGeneratedDocument(document, commitAdmission: use.cancellation)
            use.committed = true
            if case .summary = use.request.operation, let summaryCheckpoints {
                // This retained completion task owns cleanup after SQLite has
                // accepted commit. Failed/cancelled saves keep every valid map.
                try await summaryCheckpoints.remove(jobID: use.request.meetingID,
                                                     meetingID: use.request.meetingID)
            }
            finish(use, phase: .completed, document: document)
            return document
        } catch {
            // A later cache-cleanup failure must never erase/relabel a row that
            // already committed. The caller still receives the actual error.
            if use.committed { finish(use, phase: .completed, document: document) }
            else { finish(use, phase: error is CancellationError ? .cancelled : .failed) }
            throw error
        }
    }

    private func cleanup(_ use: Use) async throws {
        if let existing = use.cleanup { try await existing.value; return }
        guard let lease = use.admissionLease else { throw IntelligenceSessionError.staleRequest }
        let owned = Task { @MainActor in
            do {
                try await self.admission.cancelAndDrain(lease)
                use.released = true
                use.cleanupBlocked = false
            } catch {
                use.cleanup = nil
                throw error
            }
        }
        use.cleanup = owned
        try await owned.value
    }

    private func project(_ use: Use, phase: IntelligencePhase, document: StoredGeneratedDocument? = nil) {
        guard current === use else { return }
        state = .init(phase: phase, requestID: use.request.id, meetingID: use.request.meetingID, document: document)
    }

    private func finish(_ use: Use, phase: IntelligencePhase, document: StoredGeneratedDocument? = nil) {
        guard current === use else { return }
        project(use, phase: phase, document: document)
        if use.released { current = nil }
    }

    private static func evidence(_ value: GroundedSummaryEvidence) -> [String: Any] {
        ["source_id": value.sourceID, "start_sample": value.startSample,
         "end_sample": value.endSample, "quote": value.quote]
    }

    private static func provenance(_ values: [SummaryGenerationProvenance]) -> [[String: Any]] {
        values.map { ["model_revision": $0.modelRevision, "prompt_version": $0.promptVersion, "map_index": $0.mapIndex] }
    }

    private static func point(_ value: GroundedSummaryPoint) -> [String: Any] {
        ["text": value.text, "evidence": value.evidence.map { evidence($0) }, "provenance": provenance(value.provenance)]
    }

    private static func document(summary: GroundedSummary, request: IntelligenceRequest,
                                 revision: String) throws -> StoredGeneratedDocument {
        let actions: [[String: Any]] = summary.actions.map {
            ["task": $0.task, "owner": $0.owner.map { $0 as Any } ?? NSNull(),
             "due": $0.due.map { $0 as Any } ?? NSNull(), "evidence": $0.evidence.map { evidence($0) },
             "provenance": provenance($0.provenance)]
        }
        let payload: [String: Any] = ["schema_version": 1, "meeting_id": summary.meetingID.uuidString,
            "summary_points": summary.summaryPoints.map { point($0) },
            "decisions": summary.decisions.map { point($0) }, "actions": actions]
        let text = (summary.summaryPoints.map(\.text) + summary.decisions.map { "Decision: " + $0.text }
            + summary.actions.map { action in
                "Action: " + action.task + (action.owner.map { " — " + $0 } ?? "") + (action.due.map { " (" + $0 + ")" } ?? "")
            }).joined(separator: "\n")
        return try document(payload: payload, text: text, request: request, kind: .summary,
                            revision: revision, prompt: SummaryPipeline.currentPromptVersion, question: nil)
    }

    private static func document(answer: MeetingQuestionAnswer, request: IntelligenceRequest) throws -> StoredGeneratedDocument {
        let citations: [[String: Any]] = answer.evidence.map {
            ["source_id": $0.source.id.uuidString, "start_sample": $0.source.startSample,
             "end_sample": $0.source.endSample, "quote": $0.quote, "asr_model_revision": $0.source.modelRevision]
        }
        let payload: [String: Any] = ["schema_version": 1, "meeting_id": answer.meetingID.uuidString,
            "status": answer.status.rawValue, "evidence": citations,
            "model_revision": answer.modelRevision, "prompt_version": answer.promptVersion]
        let text = answer.status == .insufficientEvidence ? "Insufficient evidence in this meeting."
            : answer.evidence.map(\.quote).joined(separator: "\n")
        let question: String?
        if case .question(let value) = request.operation { question = value } else { question = nil }
        return try document(payload: payload, text: text, request: request, kind: .questionAnswer,
                            revision: answer.modelRevision, prompt: answer.promptVersion, question: question)
    }

    private static func document(payload: [String: Any], text: String, request: IntelligenceRequest,
                                 kind: GeneratedDocumentKind, revision: String, prompt: String,
                                 question: String?) throws -> StoredGeneratedDocument {
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        guard json.count <= 1_048_576, text.utf8.count <= 1_048_576 else { throw GeneratedDocumentStoreError.invalidInput }
        return .init(id: request.documentID, meetingID: request.meetingID, kind: kind, originalJSON: json,
            question: question, editedText: text, modelRevision: revision, promptVersion: prompt,
            createdAt: request.createdAt, modifiedAt: request.createdAt)
    }
}
