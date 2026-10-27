import Foundation
import XCTest
@testable import LocalMinutesSummary

final class StructuredJSONSchemaTests: XCTestCase {
    func testUnknownMetadataCompilesAsNullOnlyInsteadOfAnUnconstrainedString() throws {
        let grammar = try StructuredJSONSchema(fields: [
            .init(name: "owner", type: .null), .init(name: "due", type: .null)
        ]).grammar()
        XCTAssertTrue(grammar.contains("field-0 ::= \"null\" ws"))
        XCTAssertTrue(grammar.contains("field-1 ::= field-0"), "Identical null domains may share a rule")
        XCTAssertFalse(grammar.contains("field-0 ::= string"))
    }

    func testRepeatedCorrelatedChoiceDomainsFitTheExistingGrammarBudgetWithoutLosingBranches() throws {
        let branches: [StructuredJSONType] = (0..<64).map { index in
            let text = "Exact source sentence \(index)."
            return .object([
                .init(name: "source_id", type: .stringEnumeration(["budget-source-\(index)"])),
                .init(name: "quote", type: .stringEnumeration([text])),
                .init(name: "text", type: .stringEnumeration([text]))
            ])
        }
        let domain = StructuredJSONType.array(element: .alternatives(branches), maximumItems: 2)
        let grammar = try StructuredJSONSchema(fields: [
            .init(name: "summary_points", type: domain),
            .init(name: "decisions", type: domain),
            .init(name: "other_items", type: domain)
        ]).grammar()
        XCTAssertLessThanOrEqual(grammar.utf8.count, 65_536)
        for index in 0..<64 {
            XCTAssertNotNil(Data(grammar.utf8).range(of: Data(try literal(for: "budget-source-\(index)").utf8)),
                "Budget handling must retain every branch, never silently keep only a prefix")
        }
    }

    func testObjectAlternativesRetainEveryCorrelatedBranchWithoutWideningFields() throws {
        let spellings = ["A cafe\u{301} quote.", "A café quote."]
        let branches: [StructuredJSONType] = spellings.enumerated().map { index, spelling in
            .object([
                .init(name: "source_id", type: .stringEnumeration(["source-\(index)"])),
                .init(name: "quote", type: .stringEnumeration([spelling])),
                .init(name: "text", type: .stringEnumeration([spelling]))
            ])
        }
        let schema = StructuredJSONSchema(fields: [.init(name: "item", type: .alternatives(branches))])
        let grammar = try schema.grammar()
        for index in spellings.indices {
            XCTAssertNotNil(Data(grammar.utf8).range(of: Data(try literal(for: "source-\(index)").utf8)),
                "Every branch must remain reachable; compiling only the first loses valid evidence")
            XCTAssertNotNil(Data(grammar.utf8).range(of: Data(try literal(for: spellings[index]).utf8)),
                "Alternative source spelling must preserve exact Unicode bytes")
        }
        XCTAssertTrue(grammar.split(separator: "\n").contains { $0.hasPrefix("field-0 ::=") && $0.contains(" | ") },
            "The item rule must choose a complete branch rather than independent field values")
        XCTAssertFalse(grammar.contains(" ::= string\n"), "Literal-only branches must not widen into arbitrary strings")
        XCTAssertNotEqual(Data(spellings[0].utf8), Data(spellings[1].utf8))
        let invalidChoices: [[StructuredJSONType]] = [[], Array(repeating: .string, count: 257)]
        for choices in invalidChoices {
            XCTAssertThrowsError(try StructuredJSONSchema(fields: [
                .init(name: "item", type: .alternatives(choices))
            ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .invalidBounds) }
        }
    }

    func testCompilerPreservesCallerFieldOrderAndRequestedJSONTypes() throws {
        let schema = StructuredJSONSchema(fields: [
            .init(name: "action_task", type: .string), .init(name: "action_owner", type: .string),
            .init(name: "action_due", type: .string), .init(name: "decision", type: .string),
            .init(name: "budget_decided", type: .boolean),
            .init(name: "evidence", type: .stringArray(allowedValues: ["source-A", "source-B"]))
        ])
        let grammar = try schema.grammar()
        XCTAssertFalse(grammar.isEmpty)
        let root = try XCTUnwrap(grammar.split(separator: "\n").first).description
        XCTAssertTrue(root.hasPrefix("root ::= ws \"{\" ws "))
        var previous = root.startIndex
        for name in schema.fields.map(\.name) {
            let found = try XCTUnwrap(root.range(of: "\\\"\(name)\\\"", range: previous..<root.endIndex))
            previous = found.upperBound
        }
        XCTAssertTrue(grammar.contains("field-0 ::= string"))
        XCTAssertTrue(grammar.contains("field-4 ::= boolean"))
        XCTAssertTrue(grammar.contains("boolean ::= (\"true\" | \"false\") ws"))
        XCTAssertTrue(grammar.contains(try literal(for: "source-A")))
        XCTAssertTrue(grammar.contains(try literal(for: "source-B")))
        XCTAssertFalse(grammar.contains("number ::="), "Do not widen requested types to unconstrained JSON")
    }

    func testFieldsMustBeNonemptyUniqueAndSafeBoundedIdentifiers() throws {
        XCTAssertThrowsError(try StructuredJSONSchema(fields: []).grammar()) {
            XCTAssertEqual($0 as? StructuredJSONSchemaError, .emptyFields)
        }
        XCTAssertThrowsError(try StructuredJSONSchema(fields: [
            .init(name: "same", type: .string), .init(name: "same", type: .boolean)
        ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .duplicateFieldName) }
        for name in ["", "1field", "bad-name", "x\nroot ::= poison", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try StructuredJSONSchema(fields: [.init(name: name, type: .string)]).grammar()) {
                XCTAssertEqual($0 as? StructuredJSONSchemaError, .invalidFieldName)
            }
        }
        for name in ["field", "_field_2", String(repeating: "a", count: 64)] {
            XCTAssertFalse(try StructuredJSONSchema(fields: [.init(name: name, type: .string)]).grammar().isEmpty)
        }
    }

    func testEnumValuesAreJSONAndGBNFLiteralsWithoutRuleInjectionOrUnicodeLoss() throws {
        let values = ["source \"quoted\"", "C:\\source", "雪\npoison ::= \"injected\"", "Café 📝"]
        let grammar = try StructuredJSONSchema(fields: [
            .init(name: "source", type: .stringEnumeration(values)),
            .init(name: "evidence", type: .stringArray(allowedValues: values))
        ]).grammar()
        for value in values { XCTAssertTrue(grammar.contains(try literal(for: value))) }
        let lines = grammar.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.hasPrefix("root ::=") }.count, 1)
        XCTAssertFalse(lines.contains { $0.hasPrefix("poison ::=") })
        XCTAssertFalse(grammar.contains("雪\npoison"), "Source control characters must stay inside escaped literals")
        XCTAssertTrue(grammar.contains("Café 📝"))
    }

    func testEmptyScalarEnumFailsButEmptyEvidenceDomainAllowsOnlyAnEmptyArray() throws {
        XCTAssertThrowsError(try StructuredJSONSchema(fields: [
            .init(name: "source", type: .stringEnumeration([]))
        ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .emptyEnumeration) }
        let grammar = try StructuredJSONSchema(fields: [
            .init(name: "evidence", type: .stringArray(allowedValues: []))
        ]).grammar()
        XCTAssertTrue(grammar.contains("field-0 ::= \"[\" ws \"]\" ws"))
        XCTAssertFalse(grammar.contains("enum-0 ::="))
        XCTAssertFalse(grammar.contains("field-0 ::= string"))
    }

    func testGrammarByteBudgetRejectsInvalidLimitsAndNeverTruncatesACompleteGrammar() throws {
        let fields = [StructuredJSONField(name: "source", type: .string)]
        for bound in [Int.min, -1, 0, 1, 255, 65_537, Int.max] {
            XCTAssertThrowsError(try StructuredJSONSchema(fields: fields, maximumGrammarUTF8Bytes: bound).grammar()) {
                XCTAssertEqual($0 as? StructuredJSONSchemaError, .invalidBounds)
            }
        }
        let full = try StructuredJSONSchema(fields: fields).grammar()
        XCTAssertGreaterThan(full.utf8.count, 256)
        XCTAssertEqual(try StructuredJSONSchema(fields: fields, maximumGrammarUTF8Bytes: full.utf8.count).grammar(), full)
        XCTAssertThrowsError(try StructuredJSONSchema(fields: fields,
            maximumGrammarUTF8Bytes: max(256, full.utf8.count - 1)).grammar()) {
            XCTAssertEqual($0 as? StructuredJSONSchemaError, .grammarTooLarge)
        }
    }

    func testFieldAndEnumerationCollectionsAreBoundedAndDuplicateValuesRejected() throws {
        let excessiveFields = (0..<65).map { StructuredJSONField(name: "field_\($0)", type: .string) }
        XCTAssertThrowsError(try StructuredJSONSchema(fields: excessiveFields).grammar()) {
            XCTAssertEqual($0 as? StructuredJSONSchemaError, .tooManyFields)
        }
        let excessiveValues = (0..<257).map { "source-\($0)" }
        XCTAssertThrowsError(try StructuredJSONSchema(fields: [
            .init(name: "source", type: .stringEnumeration(excessiveValues))
        ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .tooManyEnumerationValues) }
        XCTAssertThrowsError(try StructuredJSONSchema(fields: [
            .init(name: "source", type: .stringEnumeration(["duplicate", "duplicate"]))
        ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .duplicateEnumerationValue) }
        XCTAssertThrowsError(try StructuredJSONSchema(fields: [
            .init(name: "evidence", type: .stringArray(allowedValues: [String(repeating: "é", count: 513)]))
        ]).grammar()) { XCTAssertEqual($0 as? StructuredJSONSchemaError, .invalidEnumerationValue) }
    }

    private func literal(for value: String) throws -> String {
        // Independent Foundation JSON encoder supplies the JSON string payload;
        // the outer quoting is the GBNF literal transport, not generated content.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
        return "\"" + json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
