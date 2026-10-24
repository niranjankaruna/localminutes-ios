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
        var compiler = Compiler(maximumBytes: maximumGrammarUTF8Bytes)
        let body = try compiler.object(fields, path: "field", depth: 0)
        let root = "root ::= ws " + body
        let grammar = ([root] + compiler.rules + [Self.sharedRules]).joined(separator: "\n")
        guard grammar.utf8.count <= maximumGrammarUTF8Bytes else {
            throw StructuredJSONSchemaError.grammarTooLarge
        }
        return grammar
    }

    /// Limits both recursive input and generated rule allocation. Array tails
    /// use only the existing GBNF optional/sequence operators, and terminate
    /// after the caller's maximum rather than widening to unbounded JSON.
    private struct Compiler {
        let maximumBytes: Int
        var rules: [String] = []
        private var emittedBytes = StructuredJSONSchema.sharedRules.utf8.count
        private var fieldCount = 0

        init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

        mutating func object(_ fields: [StructuredJSONField], path: String, depth: Int) throws -> String {
            guard depth <= 8 else { throw StructuredJSONSchemaError.invalidBounds }
            guard !fields.isEmpty else { throw StructuredJSONSchemaError.emptyFields }
            guard fields.count <= 64, fieldCount <= 1_024 - fields.count else {
                throw StructuredJSONSchemaError.tooManyFields
            }
            fieldCount += fields.count
            var names: Set<String> = []
            var members: [String] = []
            for (index, field) in fields.enumerated() {
                guard StructuredJSONSchema.validIdentifier(field.name) else {
                    throw StructuredJSONSchemaError.invalidFieldName
                }
                guard names.insert(field.name).inserted else { throw StructuredJSONSchemaError.duplicateFieldName }
                let name = "\(path)-\(index)"
                members.append("\(try StructuredJSONSchema.literal(for: field.name)) ws \":\" ws \(name)")
                try type(field.type, name: name, depth: depth + 1)
            }
            return "\"{\" ws " + members.joined(separator: " \",\" ws ") + " \"}\" ws"
        }

        mutating func type(_ value: StructuredJSONType, name: String, depth: Int) throws {
            guard depth <= 8 else { throw StructuredJSONSchemaError.invalidBounds }
            switch value {
            case .string: try append(name, "string")
            case .boolean: try append(name, "boolean")
            case .stringEnumeration(let values):
                guard !values.isEmpty else { throw StructuredJSONSchemaError.emptyEnumeration }
                let alternatives = try StructuredJSONSchema.enumAlternatives(values, maximumBytes: maximumBytes)
                try append(name, "(\(alternatives)) ws")
            case .stringArray(let values):
                let alternatives = try StructuredJSONSchema.enumAlternatives(values, maximumBytes: maximumBytes)
                if values.isEmpty {
                    try append(name, "\"[\" ws \"]\" ws")
                } else {
                    let domain = name.replacingOccurrences(of: "field-", with: "enum-")
                    try append(name, "\"[\" ws (\(domain) (\",\" ws \(domain))*)? \"]\" ws")
                    try append(domain, "(\(alternatives)) ws")
                }
            case .object(let fields):
                let body = try object(fields, path: name, depth: depth)
                try append(name, body)
            case .array(let element, let maximumItems):
                guard (1...128).contains(maximumItems) else { throw StructuredJSONSchemaError.invalidBounds }
                let item = name + "-item"
                try type(element, name: item, depth: depth + 1)
                if maximumItems == 1 {
                    try append(name, "\"[\" ws (\(item))? \"]\" ws")
                } else {
                    for remaining in 1..<maximumItems {
                        let next = remaining == 1 ? "" : " \(name)-tail-\(remaining - 1)"
                        try append("\(name)-tail-\(remaining)", "(\",\" ws \(item)\(next))?")
                    }
                    try append(name, "\"[\" ws (\(item) \(name)-tail-\(maximumItems - 1))? \"]\" ws")
                }
            case .nullable(let wrapped):
                let inner = name + "-value"
                try type(wrapped, name: inner, depth: depth + 1)
                try append(name, "(\(inner) | \"null\" ws)")
            case .integerEnumeration(let values):
                guard !values.isEmpty else { throw StructuredJSONSchemaError.emptyEnumeration }
                guard values.count <= 256 else { throw StructuredJSONSchemaError.tooManyEnumerationValues }
                var seen: Set<Int64> = []
                var literals: [String] = []
                for value in values {
                    guard seen.insert(value).inserted else { throw StructuredJSONSchemaError.duplicateEnumerationValue }
                    literals.append("\"\(value)\"")
                }
                try append(name, "(\(literals.joined(separator: " | "))) ws")
            }
        }

        private mutating func append(_ name: String, _ body: String) throws {
            guard rules.count < 1_024 else { throw StructuredJSONSchemaError.grammarTooLarge }
            let rule = "\(name) ::= \(body)"
            let bytes = rule.utf8.count + 1
            guard bytes <= maximumBytes, emittedBytes <= maximumBytes - bytes else {
                throw StructuredJSONSchemaError.grammarTooLarge
            }
            emittedBytes += bytes
            rules.append(rule)
        }
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
