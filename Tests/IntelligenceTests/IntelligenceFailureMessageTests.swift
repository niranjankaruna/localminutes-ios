import Foundation
import XCTest
import LocalMinutesSummary
import LocalMinutesQuestionAnswering
@testable import LocalMinutesIntelligence

final class IntelligenceFailureMessageTests: XCTestCase {
    func testFailuresDistinguishModelLoadingInputBudgetAndUnsupportedOutput() {
        let errors: [any Error] = [IntelligenceSessionError.transcriptMissing,
            LocalSummaryRuntimeError.invalidModel, LocalSummaryRuntimeError.contextUnavailable,
            LocalSummaryRuntimeError.contextExceeded, LocalSummaryRuntimeError.outputLimitExceeded,
            GroundedSummaryError.unsupportedClaim, LocalSummaryRuntimeError.generationFailed]
        let messages = errors.map { IntelligenceFailureMessage.message(for: $0) }
        XCTAssertEqual(Set(messages).count, errors.count)
        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(IntelligenceFailureMessage.message(for: SummaryChunkPlannerError.oversizedSegment("private-id")),
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
