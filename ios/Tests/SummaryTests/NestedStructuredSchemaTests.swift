import XCTest
@testable import LocalMinutesSummary

/// Activate before implementing the recursive type additions. Existing six
/// compiler tests and four actual semantic cases must remain unchanged.
final class NestedStructuredSchemaTests: XCTestCase {
    func testBoundedNestedNullableCitationSchemaCompilesMetadataWithoutAnswerLiterals() throws {
        let citation: StructuredJSONType = .object([
            .init(name: "source_id", type: .stringEnumeration(["source-A", "source-B"])),
            .init(name: "start_sample", type: .integerEnumeration([0, 16_000])),
            .init(name: "end_sample", type: .integerEnumeration([16_000, 32_000])),
            .init(name: "quote", type: .string)
        ])
        let action: StructuredJSONType = .object([
            .init(name: "task", type: .string), .init(name: "owner", type: .nullable(.string)),
            .init(name: "due", type: .nullable(.string)),
            .init(name: "evidence", type: .array(element: citation, maximumItems: 2))
        ])
        let schema = StructuredJSONSchema(fields: [.init(name: "actions", type: .array(element: action, maximumItems: 4))])
        let grammar: String
        do { grammar = try schema.grammar() }
        catch { return XCTFail("The caller's bounded nested/nullable citation schema must compile: \(error)") }
        XCTAssertFalse(grammar.isEmpty)
        XCTAssertTrue(grammar.contains("\\\"owner\\\""))
        XCTAssertTrue(grammar.contains("\\\"due\\\""))
        XCTAssertTrue(grammar.contains("null"))
        XCTAssertTrue(grammar.contains("16000"))
        XCTAssertTrue(grammar.contains("32000"))
        XCTAssertTrue(grammar.contains("source-A"))
        XCTAssertLessThanOrEqual(grammar.utf8.count, schema.maximumGrammarUTF8Bytes)
        for count in [0, 129] {
            XCTAssertThrowsError(try StructuredJSONSchema(fields: [
                .init(name: "items", type: .array(element: .string, maximumItems: count))
            ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .invalidBounds) }
        }
    }
}
