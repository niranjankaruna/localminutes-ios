import Foundation
import XCTest
@testable import LocalMinutesSummary

final class SummaryOverviewFormattingTests: XCTestCase {
    func testOverviewRetainsEachPointAndRemovesOnlyListMarkersAndBlankLines() {
        XCTAssertEqual(SummaryOverviewFormatting.points("  • Discussed the release.\r\n\n- Review on Friday.\n* Sign-off is still pending.  "),
            ["Discussed the release.", "Review on Friday.", "Sign-off is still pending."])
        XCTAssertEqual(SummaryOverviewFormatting.points("A legacy overview paragraph."), ["A legacy overview paragraph."])
        XCTAssertEqual(SummaryOverviewFormatting.points(" \n\t"), [])
    }

    func testMetadataUsesSuppliedMeetingTimestampAndTimeZone() throws {
        let locale = Locale(identifier: "en_GB")
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = Date(timeIntervalSince1970: 0)
        let details = SummaryOverviewFormatting.meetingDetails(startedAt: start, locale: locale, timeZone: utc)
        XCTAssertEqual(details, ["Date: 1 January 1970", "Time: 00:00 (GMT)"])
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: -3_600))
        let shifted = SummaryOverviewFormatting.meetingDetails(startedAt: start, locale: locale, timeZone: zone)
        XCTAssertEqual(shifted[0], "Date: 31 December 1969")
        XCTAssertTrue(shifted[1].contains("23:00"))
    }
}
