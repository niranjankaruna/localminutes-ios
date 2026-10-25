#if os(iOS)
import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import LocalMinutes

/// Actual notification name, session lifecycle, installer hashes/leases and
/// SQLite. The sole runtime boundary holds allocation/work/unload; it produces
/// no generated text and establishes neither inference quality nor device OOM.
@MainActor
final class NativeIntelligenceMemoryPressureTests: XCTestCase {
    func testDefaultServicesOwnTheMemoryWarningMonitorIndependentlyOfViews() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-memory-services-\(UUID().uuidString)", isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root)
        await services.initialize()
        XCTAssertNotNil(services.intelligenceMemoryPressureMonitor,
            "App services must retain the actual memory-warning observer without a view subscription")
        try await services.store.close()
        try removeMemoryRoot(root, parent: parent, prefix: "localminutes-memory-services-")
    }

    func testDuplicateWarningsCancelCurrentGenerationButHoldWorkerAndModelUntilDrainAndUnloadFinish() async throws {
        let f = try await MemoryPressureFixture.create()
        let center = NotificationCenter()
        let slot = MemoryPressureSessionSlot()
        let monitor = IntelligenceMemoryPressureMonitor(center: center, activeSession: { slot.session })
        // A monitor created before selection must resolve the currently retained
        // session when the warning arrives, rather than capture an idle default.
        slot.session = f.session
        let operation = Task { try await f.session.run(f.request) }
        do {
            let working = await memoryEventually { await f.runtime.workStarted }
            XCTAssertTrue(working)
            guard working else { await f.settle(operation); try await f.close(); return }
            let held = try XCTUnwrap(f.admission.snapshot().lease)
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            let draining = await memoryEventually { f.session.snapshot().phase == .draining }
            XCTAssertTrue(draining, "Actual memory warnings must request cancellation of the active intelligence worker")
            guard draining else { await f.settle(operation); try await f.close(); return }
            XCTAssertEqual(f.admission.snapshot().lease, held)
            try await assertMemoryModelInUse(f)
            let beforeRelease = await f.runtime.events
            XCTAssertEqual(beforeRelease, ["work.begin"], "Native unload cannot race a still-running worker")
            await f.runtime.releaseWork()
            let unloading = await memoryEventually { await f.runtime.unloadStarted }
            XCTAssertTrue(unloading)
            guard unloading else { await f.settle(operation); try await f.close(); return }
            XCTAssertEqual(f.admission.snapshot().phase, .draining)
            try await assertMemoryModelInUse(f)
            let unloadCalls = await f.runtime.unloadCalls
            XCTAssertEqual(unloadCalls, 1)
            await f.runtime.releaseUnload()
            do { _ = try await operation.value; XCTFail("Memory-cancelled work must not save generated content") }
            catch is CancellationError {}
            let idle = await memoryEventually { f.admission.snapshot().phase == .idle }
            XCTAssertTrue(idle)
            XCTAssertEqual(f.session.snapshot().phase, .cancelled)
            let documents = try await f.store.generatedDocuments(meetingID: f.meetingID)
            let original = try await f.store.transcript(meetingID: f.meetingID)
            XCTAssertTrue(documents.isEmpty); XCTAssertEqual(original, [f.segment])
            try await f.models.remove(modelID: f.manifest.modelID)
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            await settleMemoryWarningDelivery()
            let events = await f.runtime.events
            XCTAssertEqual(events, ["work.begin", "work.drained", "unload.begin", "unload.end"])
            let loads = await f.loader.loads
            XCTAssertEqual(loads, 1)
            withExtendedLifetime(monitor) {}
            try await f.close()
        } catch {
            await f.settle(operation); try? await f.close(); throw error
        }
    }

    func testWarningDuringAllocationJoinsLoadingThenUnloadsWithoutBeginningGeneration() async throws {
        let f = try await MemoryPressureFixture.create(holdAllocation: true)
        let center = NotificationCenter()
        let monitor = IntelligenceMemoryPressureMonitor(center: center, activeSession: { f.session })
        let operation = Task { try await f.session.run(f.request) }
        do {
            let loading = await memoryEventually { await f.loader.started }
            XCTAssertTrue(loading)
            guard loading else { await f.settle(operation); try await f.close(); return }
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            let draining = await memoryEventually { f.session.snapshot().phase == .draining }
            XCTAssertTrue(draining, "An actual memory warning must close an in-flight model load")
            guard draining else { await f.settle(operation); try await f.close(); return }
            try await assertMemoryModelInUse(f)
            let unloadCalls = await f.runtime.unloadCalls
            XCTAssertEqual(unloadCalls, 0)
            await f.loader.releaseAllocation()
            let unloading = await memoryEventually { await f.runtime.unloadStarted }
            XCTAssertTrue(unloading)
            guard unloading else { await f.settle(operation); try await f.close(); return }
            let workStarted = await f.runtime.workStarted
            XCTAssertFalse(workStarted)
            try await assertMemoryModelInUse(f)
            await f.runtime.releaseUnload()
            do { _ = try await operation.value; XCTFail("Cancelled allocation cannot begin generation") }
            catch is CancellationError {}
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
            try await f.models.remove(modelID: f.manifest.modelID)
            withExtendedLifetime(monitor) {}
            try await f.close()
        } catch {
            await f.settle(operation); try? await f.close(); throw error
        }
    }

    func testIdleOrAbsentIntelligenceWarningsNeverCancelActiveStreamingASROrStartALocalModel() async throws {
        let f = try await MemoryPressureFixture.create()
        let center = NotificationCenter()
        let slot = MemoryPressureSessionSlot()
        let monitor = IntelligenceMemoryPressureMonitor(center: center, activeSession: { slot.session })
        let captureBoundary = MemoryPressureASRResource()
        let lease = try f.admission.acquire(purpose: .streamingASR, requestID: UUID(), resource: captureBoundary)
        do {
            // Actual gate ownership is the capture boundary; this does not
            // substitute for a physical microphone or locked recording result.
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            slot.session = f.session
            center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
            await settleMemoryWarningDelivery()
            XCTAssertEqual(f.admission.snapshot().lease, lease)
            XCTAssertEqual(f.session.snapshot().phase, .idle)
            XCTAssertEqual(captureBoundary.cancellations, 0)
            XCTAssertEqual(captureBoundary.drains, 0)
            XCTAssertEqual(captureBoundary.unloads, 0)
            let loads = await f.loader.loads
            XCTAssertEqual(loads, 0)
            try await f.admission.cancelAndDrain(lease)
            withExtendedLifetime(monitor) {}
            try await f.close()
        } catch {
            try? await f.admission.cancelAndDrain(lease); try? await f.close(); throw error
        }
    }
}

@MainActor private final class MemoryPressureSessionSlot { var session: IntelligenceSession? }

private actor MemoryPressureRuntime: IntelligenceRuntime {
    private(set) var workStarted = false
    private(set) var unloadStarted = false
    private(set) var unloadCalls = 0
    private(set) var events: [String] = []
    private var workReleased = false
    private var unloadReleased = false
    private var workContinuation: CheckedContinuation<Void, Never>?
    private var unloadContinuation: CheckedContinuation<Void, Never>?

    func promptTokenCount(prompt: String) async throws -> Int {
        workStarted = true; events.append("work.begin")
        if !workReleased { await withCheckedContinuation { workContinuation = $0 } }
        events.append("work.drained")
        try Task.checkCancellation()
        throw MemoryPressureFixtureError.unexpectedGeneration
    }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        throw MemoryPressureFixtureError.unexpectedGeneration
    }
    func unload() async {
        unloadCalls += 1; unloadStarted = true; events.append("unload.begin")
        if !unloadReleased { await withCheckedContinuation { unloadContinuation = $0 } }
        events.append("unload.end")
    }
    func releaseWork() { workReleased = true; workContinuation?.resume(); workContinuation = nil }
    func releaseUnload() { unloadReleased = true; unloadContinuation?.resume(); unloadContinuation = nil }
}

private actor MemoryPressureLoader {
    let runtime: MemoryPressureRuntime
    private let held: Bool
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private(set) var loads = 0
    init(runtime: MemoryPressureRuntime, held: Bool) { self.runtime = runtime; self.held = held }
    func load(_ model: VerifiedModel) async -> any IntelligenceRuntime {
        loads += 1; started = true
        if held && !released { await withCheckedContinuation { continuation = $0 } }
        return runtime
    }
    func releaseAllocation() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class MemoryPressureASRResource: HeavyModelResourceLifecycle {
    var cancellations = 0, drains = 0, unloads = 0
    func requestCancellation() { cancellations += 1 }
    func drain() async throws { drains += 1 }
    func unloadAndReleaseModel() async throws { unloads += 1 }
}

private enum MemoryPressureFixtureError: Error { case unexpectedGeneration }

@MainActor private struct MemoryPressureFixture {
    let root: URL
    let parent: URL
    let meetingID: UUID
    let segment: StoredTranscriptSegment
    let manifest: ModelManifest
    let models: ModelInstallationManager
    let store: SQLiteMeetingStore
    let admission: HeavyModelAdmission
    let runtime: MemoryPressureRuntime
    let loader: MemoryPressureLoader
    let session: IntelligenceSession
    var request: IntelligenceRequest { .init(meetingID: meetingID, operation: .summary) }

    static func create(holdAllocation: Bool = false) async throws -> Self {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-memory-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let bytes = Data("Original synthetic allocation fixture; deliberately not inference weights.".utf8)
        try bytes.write(to: source.appendingPathComponent("memory.gguf"))
        let revision = String(repeating: "a", count: 40)
        let repository = URL(string: "https://huggingface.co/example/memory-boundary")!
        let manifest = ModelManifest(modelID: "memory-boundary", purpose: .summary, upstreamRepository: repository,
            revision: revision, licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic lifecycle fixture, CC0-1.0.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary, fileName: "memory.gguf",
                byteCount: Int64(bytes.count), sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                downloadURL: repository.appendingPathComponent("resolve/\(revision)/memory.gguf"),
                digestProvenance: .independentlyDownloaded)])
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        _ = try await models.importDirectory(source, manifest: manifest)
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        let meetingID = UUID()
        try await store.createMeeting(.init(id: meetingID, title: "Synthetic memory boundary", createdAt: Date(timeIntervalSince1970: 1),
            recordingState: .completed, capturedSampleCount: 16_000))
        let segment = StoredTranscriptSegment(id: UUID(), meetingID: meetingID, sequence: 0, startSample: 0,
            endSample: 16_000, text: "Original synthetic source remains unchanged.", modelRevision: "synthetic-asr")
        try await store.appendFinalizedSegments([segment], to: meetingID)
        let admission = HeavyModelAdmission()
        let runtime = MemoryPressureRuntime()
        let loader = MemoryPressureLoader(runtime: runtime, held: holdAllocation)
        let session = IntelligenceSession(store: store, models: models, admission: admission, manifest: manifest,
            runtimeLoader: { await loader.load($0) })
        return .init(root: root, parent: parent, meetingID: meetingID, segment: segment, manifest: manifest,
            models: models, store: store, admission: admission, runtime: runtime, loader: loader, session: session)
    }
    func settle(_ operation: Task<StoredGeneratedDocument, Error>) async {
        operation.cancel()
        await loader.releaseAllocation(); await runtime.releaseWork(); await runtime.releaseUnload()
        _ = await operation.result
    }
    func close() async throws {
        try await store.close()
        try removeMemoryRoot(root, parent: parent, prefix: "localminutes-memory-runtime-")
    }
}

@MainActor private func assertMemoryModelInUse(_ fixture: MemoryPressureFixture,
    file: StaticString = #filePath, line: UInt = #line) async throws {
    do { try await fixture.models.remove(modelID: fixture.manifest.modelID); XCTFail("A native lifecycle still holds its verified installation", file: file, line: line) }
    catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse, file: file, line: line) }
}

@MainActor private func memoryEventually(_ predicate: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !(await predicate()) {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor private func settleMemoryWarningDelivery() async {
    for _ in 0..<8 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
}

@MainActor private func removeMemoryRoot(_ root: URL, parent: URL, prefix: String) throws {
    guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix(prefix),
          UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
          root.resolvingSymlinksInPath().standardizedFileURL == root else {
        XCTFail("Refuse cleanup outside owned memory-warning fixture"); return
    }
    try FileManager.default.removeItem(at: root)
}
#endif
