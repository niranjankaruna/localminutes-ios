import Foundation
import XCTest
import LocalMinutesSummary
import LocalMinutesPersistence
import LocalMinutesQuestionAnswering
@testable import LocalMinutesIntelligence

final class IntelligenceFailureMessageTests: XCTestCase {
    func testCheckpointFormatFailureIdentifiesTheAppStorageBoundaryInsteadOfBlamingTheModel() {
        let error = SummaryCheckpointError.invalidInput
        let message = IntelligenceFailureMessage.message(for: error)
        XCTAssertTrue(message.contains("checkpoint format"))
        XCTAssertFalse(message.contains("another summary model"))
        XCTAssertEqual(IntelligenceFailureMessage.code(for: error), "LM-CHECKPOINT-FORMAT")
        XCTAssertEqual(IntelligenceFailureMessage.code(for: SummaryCheckpointError.corruptCheckpoint), "LM-CHECKPOINT-CORRUPT")
    }

    func testFailuresDistinguishModelLoadingInputBudgetAndUnsupportedOutput() {
        let errors: [any Error] = [IntelligenceSessionError.transcriptMissing,
            LocalSummaryRuntimeError.invalidModel, LocalSummaryRuntimeError.contextUnavailable,
            LocalSummaryRuntimeError.contextExceeded, LocalSummaryRuntimeError.outputLimitExceeded,
            NarrativeSummaryError.unsupportedEvidence, LocalSummaryRuntimeError.generationFailed]
        let messages = errors.map { IntelligenceFailureMessage.message(for: $0) }
        XCTAssertEqual(Set(messages).count, errors.count)
        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(IntelligenceFailureMessage.message(for: NarrativeSummaryError.contextExceeded),
                       IntelligenceFailureMessage.message(for: LocalSummaryRuntimeError.contextExceeded))
    }

    func testDiagnosticMessageNeverExposesNativeErrorTextOrPrivatePaths() {
        let error = NSError(domain: "private-transcript", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "/private/meeting-secret.txt: private transcript"])
        let message = IntelligenceFailureMessage.message(for: error)
        XCTAssertFalse(message.contains("private"))
        XCTAssertFalse(message.contains("meeting-secret"))
    }
}
