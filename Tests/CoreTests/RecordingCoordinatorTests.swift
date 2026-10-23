import Foundation
import XCTest
@testable import LocalMinutesCore

private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let ready = RecordingReadiness(audioSessionActive: true, firstBufferAccepted: true, activityActive: true)

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    private func recordingCoordinator() async -> RecordingCoordinator {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        _ = await coordinator.preparationSucceeded(for: firstID)
        await coordinator.updateReadiness(ready, for: firstID)
        return coordinator
    }

    func testInitialStateIsIdleWithoutARecordingBadge() async {
        let value = await RecordingCoordinator().snapshot()
        XCTAssertEqual(value.phase, .idle)
        XCTAssertNil(value.sessionID)
        XCTAssertFalse(value.cleanupPending)
        XCTAssertFalse(value.readiness.firstBufferAccepted)
    }

    func testStartEntersPreparingAndEmitsPreparation() async {
        let coordinator = RecordingCoordinator()
        let command = await coordinator.start(sessionID: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(command, .prepare(firstID))
        XCTAssertEqual(value.phase, .preparing)
        XCTAssertEqual(value.sessionID, firstID)
        XCTAssertFalse(value.readiness.firstBufferAccepted)
    }

    func testConcurrentStartsEmitExactlyOnePreparation() async {
        let coordinator = RecordingCoordinator()
        let commands = await withTaskGroup(of: RecordingCommand?.self, returning: [RecordingCommand].self) { group in
            for _ in 0..<64 {
                group.addTask { await coordinator.start(sessionID: UUID()) }
            }
            var emitted: [RecordingCommand] = []
            for await command in group { if let command { emitted.append(command) } }
            return emitted
        }
        XCTAssertEqual(commands.count, 1)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .preparing)
        if let id = value.sessionID { XCTAssertEqual(commands, [.prepare(id)]) }
        else { XCTFail("The single preparation must own a session") }
    }

    func testDuplicatePreparationAndStartsCannotActivateTwice() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        let duplicate = await coordinator.start(sessionID: secondID)
        let activation = await coordinator.preparationSucceeded(for: firstID)
        let repeated = await coordinator.preparationSucceeded(for: firstID)
        XCTAssertNil(duplicate)
        XCTAssertEqual(activation, .activate(firstID))
        XCTAssertNil(repeated)
    }

    func testRecordingRequiresAudioSessionFirstBufferAndActivity() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        _ = await coordinator.preparationSucceeded(for: firstID)
        for readiness in [
            RecordingReadiness(audioSessionActive: false, firstBufferAccepted: true, activityActive: true),
            RecordingReadiness(audioSessionActive: true, firstBufferAccepted: false, activityActive: true),
            RecordingReadiness(audioSessionActive: true, firstBufferAccepted: true, activityActive: false)
        ] {
            await coordinator.updateReadiness(readiness, for: firstID)
            let value = await coordinator.snapshot()
            XCTAssertEqual(value.phase, .preparing)
        }
        await coordinator.updateReadiness(ready, for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .recording)
        XCTAssertEqual(value.readiness, ready)
    }

    func testReadySignalBeforePreparationCannotFabricateRecording() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        await coordinator.updateReadiness(ready, for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .preparing)
        XCTAssertFalse(value.readiness.firstBufferAccepted)
    }

    func testRepeatedStartWhileRecordingPreservesOriginalSession() async {
        let coordinator = await recordingCoordinator()
        let command = await coordinator.start(sessionID: secondID)
        let value = await coordinator.snapshot()
        XCTAssertNil(command)
        XCTAssertEqual(value.sessionID, firstID)
        XCTAssertEqual(value.phase, .recording)
    }

    func testStopWhileIdleDoesNothing() async {
        let coordinator = RecordingCoordinator()
        let first = await coordinator.stop()
        let second = await coordinator.stop()
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func testCancellationDuringPreparationRejectsLateModelCompletion() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        let command = await coordinator.stop()
        let latePreparation = await coordinator.preparationSucceeded(for: firstID)
        await coordinator.updateReadiness(ready, for: firstID)
        let stopping = await coordinator.snapshot()
        XCTAssertEqual(command, .cancelPreparation(firstID))
        XCTAssertNil(latePreparation)
        XCTAssertEqual(stopping.phase, .stopping)
        XCTAssertTrue(stopping.cleanupPending)
        await coordinator.captureStopped(for: firstID)
        let stopped = await coordinator.snapshot()
        XCTAssertEqual(stopped.phase, .idle)
        XCTAssertNil(stopped.sessionID)
    }

    func testStartDuringStopCannotTakeOverTheOldPipeline() async {
        let coordinator = await recordingCoordinator()
        _ = await coordinator.stop()
        let next = await coordinator.start(sessionID: secondID)
        await coordinator.updateReadiness(ready, for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertNil(next)
        XCTAssertEqual(value.phase, .stopping)
        XCTAssertEqual(value.sessionID, firstID)
    }

    func testStopDuringActivationFlushesOnceAndRejectsLateReadiness() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        _ = await coordinator.preparationSucceeded(for: firstID)
        let command = await coordinator.stop()
        let repeated = await coordinator.stop()
        let replacement = await coordinator.start(sessionID: secondID)
        await coordinator.updateReadiness(ready, for: firstID)
        let lateActivation = await coordinator.preparationSucceeded(for: firstID)
        let stopping = await coordinator.snapshot()
        XCTAssertEqual(command, .stopAndFlush(firstID))
        XCTAssertNil(repeated)
        XCTAssertNil(replacement)
        XCTAssertNil(lateActivation)
        XCTAssertEqual(stopping.phase, .stopping)
        XCTAssertFalse(stopping.readiness.firstBufferAccepted)
        XCTAssertTrue(stopping.cleanupPending)
        await coordinator.captureStopped(for: firstID)
        let stopped = await coordinator.snapshot()
        XCTAssertEqual(stopped.phase, .idle)
        let next = await coordinator.start(sessionID: secondID)
        XCTAssertEqual(next, .prepare(secondID))
    }

    func testConcurrentStopsEmitExactlyOneFlushAndCompleteOnlyAfterAcknowledgement() async {
        let coordinator = await recordingCoordinator()
        let commands = await withTaskGroup(of: RecordingCommand?.self, returning: [RecordingCommand].self) { group in
            for _ in 0..<64 { group.addTask { await coordinator.stop() } }
            var emitted: [RecordingCommand] = []
            for await command in group { if let command { emitted.append(command) } }
            return emitted
        }
        XCTAssertEqual(commands, [.stopAndFlush(firstID)])
        let stopping = await coordinator.snapshot()
        XCTAssertEqual(stopping.phase, .stopping)
        await coordinator.captureStopped(for: firstID)
        let stopped = await coordinator.snapshot()
        XCTAssertEqual(stopped.phase, .completed)
        XCTAssertFalse(stopped.cleanupPending)
        let next = await coordinator.start(sessionID: secondID)
        XCTAssertEqual(next, .prepare(secondID))
    }

    func testStaleEventsCannotChangeANewerSession() async {
        let coordinator = await recordingCoordinator()
        _ = await coordinator.stop()
        await coordinator.captureStopped(for: firstID)
        _ = await coordinator.start(sessionID: secondID)
        let activation = await coordinator.preparationSucceeded(for: firstID)
        let interruption = await coordinator.interrupt(for: firstID)
        let failure = await coordinator.fail(.writeFailed, for: firstID)
        await coordinator.updateReadiness(ready, for: firstID)
        await coordinator.captureStopped(for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertNil(activation)
        XCTAssertNil(interruption)
        XCTAssertNil(failure)
        XCTAssertEqual(value.sessionID, secondID)
        XCTAssertEqual(value.phase, .preparing)
    }

    func testInterruptionRemainsExplicitAfterCleanup() async {
        let coordinator = await recordingCoordinator()
        let command = await coordinator.interrupt(for: firstID)
        let blocked = await coordinator.start(sessionID: secondID)
        XCTAssertEqual(command, .stopAndFlush(firstID))
        XCTAssertNil(blocked)
        await coordinator.captureStopped(for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .interrupted)
        XCTAssertFalse(value.cleanupPending)
        let next = await coordinator.start(sessionID: secondID)
        XCTAssertEqual(next, .prepare(secondID))
    }

    func testDeniedPreparationHasAnExplicitFailureAndCancelsResources() async {
        let coordinator = RecordingCoordinator()
        _ = await coordinator.start(sessionID: firstID)
        let command = await coordinator.fail(.microphoneDenied, for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(command, .cancelPreparation(firstID))
        XCTAssertEqual(value.phase, .failed)
        XCTAssertEqual(value.failure, .microphoneDenied)
        XCTAssertTrue(value.cleanupPending)
        let blocked = await coordinator.start(sessionID: secondID)
        XCTAssertNil(blocked)
        await coordinator.captureStopped(for: firstID)
        let stopped = await coordinator.snapshot()
        XCTAssertEqual(stopped.phase, .failed)
    }

    func testStorageFailurePreservesRecoverableStatus() async {
        let coordinator = await recordingCoordinator()
        let command = await coordinator.fail(.storageFull, for: firstID)
        XCTAssertEqual(command, .stopAndFlush(firstID))
        await coordinator.captureStopped(for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .recoverableFailure)
        XCTAssertEqual(value.failure, .storageFull)
        XCTAssertFalse(value.cleanupPending)
    }

    func testFlushFailureCannotBecomeCompleted() async {
        let coordinator = await recordingCoordinator()
        _ = await coordinator.stop()
        let repeated = await coordinator.fail(.writeFailed, for: firstID)
        XCTAssertNil(repeated)
        await coordinator.captureStopped(for: firstID)
        let value = await coordinator.snapshot()
        XCTAssertEqual(value.phase, .recoverableFailure)
        XCTAssertEqual(value.failure, .writeFailed)
    }
}
