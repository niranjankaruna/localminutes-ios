import Foundation

public indirect enum StructuredJSONType: Equatable, Sendable {
    case string
    case boolean
    case stringEnumeration([String])
    case stringArray(allowedValues: [String])
    case object([StructuredJSONField])
    case array(element: StructuredJSONType, maximumItems: Int)
    case nullable(StructuredJSONType)
    case integerEnumeration([Int64])
}

public struct StructuredJSONField: Equatable, Sendable {
    public let name: String
    public let type: StructuredJSONType

    public init(name: String, type: StructuredJSONType) {
        self.name = name
        self.type = type
    }
}

public enum StructuredJSONSchemaError: Error, Equatable, Sendable {
    case emptyFields, invalidFieldName, duplicateFieldName, tooManyFields
    case emptyEnumeration, duplicateEnumerationValue, invalidEnumerationValue, tooManyEnumerationValues
    case invalidBounds, grammarTooLarge
    case unsupportedType
}

/// Caller-owned field order/types and supplied evidence IDs. No answer values
/// or model readiness are inferred from a schema.
public struct StructuredJSONSchema: Equatable, Sendable {
    public let fields: [StructuredJSONField]
    public let maximumGrammarUTF8Bytes: Int

    public init(fields: [StructuredJSONField], maximumGrammarUTF8Bytes: Int = 65_536) {
        self.fields = fields
        self.maximumGrammarUTF8Bytes = maximumGrammarUTF8Bytes
    }

    public func grammar() throws -> String {
        guard (256...65_536).contains(maximumGrammarUTF8Bytes) else {
            throw StructuredJSONSchemaError.invalidBounds
        }
        guard !fields.isEmpty else { throw StructuredJSONSchemaError.emptyFields }
        guard fields.count <= 64 else { throw StructuredJSONSchemaError.tooManyFields }
        var names: Set<String> = []
        var members: [String] = []
        var rules: [String] = []
        for (index, field) in fields.enumerated() {
            guard Self.validIdentifier(field.name) else { throw StructuredJSONSchemaError.invalidFieldName }
            guard names.insert(field.name).inserted else { throw StructuredJSONSchemaError.duplicateFieldName }
            members.append("\(try Self.literal(for: field.name)) ws \":\" ws field-\(index)")
            switch field.type {
            case .string:
                rules.append("field-\(index) ::= string")
            case .boolean:
                rules.append("field-\(index) ::= boolean")
            case .stringEnumeration(let values):
                guard !values.isEmpty else { throw StructuredJSONSchemaError.emptyEnumeration }
                let alternatives = try Self.enumAlternatives(values, maximumBytes: maximumGrammarUTF8Bytes)
                rules.append("field-\(index) ::= (\(alternatives)) ws")
            case .stringArray(let values):
                let alternatives = try Self.enumAlternatives(values, maximumBytes: maximumGrammarUTF8Bytes)
                if values.isEmpty {
                    rules.append("field-\(index) ::= \"[\" ws \"]\" ws")
                } else {
                    rules.append("field-\(index) ::= \"[\" ws (enum-\(index) (\",\" ws enum-\(index))*)? \"]\" ws")
                    rules.append("enum-\(index) ::= (\(alternatives)) ws")
                }
            case .object, .array, .nullable, .integerEnumeration:
                throw StructuredJSONSchemaError.unsupportedType
            }
            // Reject growing domains before constructing another field. The
            // final check below includes all separators and root punctuation.
            let used = members.reduce(0) { $0 + $1.utf8.count }
                + rules.reduce(0) { $0 + $1.utf8.count } + Self.sharedRules.utf8.count
            guard used <= maximumGrammarUTF8Bytes else { throw StructuredJSONSchemaError.grammarTooLarge }
        }
        let root = "root ::= ws \"{\" ws " + members.joined(separator: " \",\" ws ") + " \"}\" ws"
        let grammar = ([root] + rules + [Self.sharedRules]).joined(separator: "\n")
        guard grammar.utf8.count <= maximumGrammarUTF8Bytes else {
            throw StructuredJSONSchemaError.grammarTooLarge
        }
        return grammar
    }

    private static func validIdentifier(_ name: String) -> Bool {
        let bytes = name.utf8
        guard !bytes.isEmpty, bytes.count <= 64, let first = bytes.first,
              isLetter(first) || first == 95 else { return false }
        return bytes.allSatisfy { isLetter($0) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    private static func enumAlternatives(_ values: [String], maximumBytes: Int) throws -> String {
        guard values.count <= 256 else { throw StructuredJSONSchemaError.tooManyEnumerationValues }
        // Preserve exact source bytes, including distinct Unicode combining
        // forms. Swift's canonical String equality must not silently merge IDs.
        var seen: Set<Data> = []
        var literals: [String] = []
        var encodedBytes = 0
        for value in values {
            guard value.utf8.count <= 1_024 else { throw StructuredJSONSchemaError.invalidEnumerationValue }
            let bytes = Data(value.utf8)
            guard seen.insert(bytes).inserted else { throw StructuredJSONSchemaError.duplicateEnumerationValue }
            let encoded = try literal(for: value)
            let next = encodedBytes + encoded.utf8.count + (literals.isEmpty ? 0 : 3)
            guard next <= maximumBytes else { throw StructuredJSONSchemaError.grammarTooLarge }
            encodedBytes = next
            literals.append(encoded)
        }
        return literals.joined(separator: " | ")
    }

    private static func literal(for value: String) throws -> String {
        // First encode an actual JSON string; then quote those JSON bytes as a
        // GBNF terminal. Source quotes/control characters cannot introduce rules.
        guard let json = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw StructuredJSONSchemaError.invalidEnumerationValue
        }
        return "\"" + json.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    private static let sharedRules = #"""
    boolean ::= ("true" | "false") ws
    string ::= "\"" json-char* "\"" ws
    json-char ::= [^"\\\x00-\x1F] | "\\" json-escape
    json-escape ::= ["\\/bfnrt] | "u" hex hex hex hex
    hex ::= [0-9a-fA-F]
    ws ::= [ \t\n\r]*
    """#
}
