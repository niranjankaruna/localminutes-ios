import Foundation
import XCTest
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

final class AppleGeneratedJSONTests: XCTestCase {
    private var schema: StructuredJSONSchema {
        .init(fields: [.init(name: "actions", type: .array(element: .object([
            .init(name: "task", type: .string), .init(name: "owner", type: .nullable(.string)),
            .init(name: "due", type: .nullable(.string))
        ]), maximumItems: 16))])
    }

    func testOmittedAppleOptionalOwnersAndDatesBecomeExplicitNullWithoutInventingFacts() throws {
        let json = #"{"actions":[{"task":"Ship the release"}]}"#
        let output = try AppleGeneratedJSON.completeOptionalFields(json, schema: schema)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let action = try XCTUnwrap((object["actions"] as? [[String: Any]])?.first)
        XCTAssertEqual(action["task"] as? String, "Ship the release")
        XCTAssertTrue(action["owner"] is NSNull, "An omitted optional value means unknown, never an inferred person")
        XCTAssertTrue(action["due"] is NSNull, "Unknown dates must satisfy the existing explicit-null document schema")
    }

    func testProvidedValuesAndUnexpectedKeysSurviveForTheExistingStrictValidatorToCheck() throws {
        let json = #"{"actions":[{"task":"Original quote","owner":"Alex","due":null,"unexpected":"reject me"}]}"#
        let result = try AppleGeneratedJSON.completeOptionalFields(json, schema: schema)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary,
            try JSONSerialization.jsonObject(with: Data(result.utf8)) as? NSDictionary)
    }

    func testMalformedAndOversizedAppleOutputFailBeforeDocumentValidation() {
        XCTAssertThrowsError(try AppleGeneratedJSON.completeOptionalFields("not JSON", schema: schema))
        XCTAssertThrowsError(try AppleGeneratedJSON.completeOptionalFields(String(repeating: " ", count: 65_537), schema: schema))
    }

    func testNullOnlyActionMetadataIsRestoredAcrossCorrelatedBranches() throws {
        let schema = StructuredJSONSchema(fields: [.init(name: "actions", type: .array(element: .alternatives([
            .object([.init(name: "task", type: .stringEnumeration(["The checklist needs review."])),
                     .init(name: "owner", type: .null), .init(name: "due", type: .null)]),
            .object([.init(name: "task", type: .stringEnumeration(["Leo: I will write the guide by Thursday."])),
                     .init(name: "owner", type: .nullable(.stringEnumeration(["Leo"]))),
                     .init(name: "due", type: .nullable(.stringEnumeration(["Thursday"])))]),
        ]), maximumItems: 2))])
        let json = #"{"actions":[{"task":"The checklist needs review."},{"task":"Leo: I will write the guide by Thursday.","owner":"Leo","due":"Thursday"}]}"#
        let result = try AppleGeneratedJSON.completeOptionalFields(json, schema: schema)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        XCTAssertTrue(actions[0]["owner"] is NSNull)
        XCTAssertTrue(actions[0]["due"] is NSNull)
        XCTAssertEqual(actions[1]["owner"] as? String, "Leo")
        XCTAssertEqual(actions[1]["due"] as? String, "Thursday")
    }
}
