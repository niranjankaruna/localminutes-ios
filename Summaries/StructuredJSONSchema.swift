import Foundation

public enum StructuredJSONType: Equatable, Sendable {
    case string
    case boolean
    case stringEnumeration([String])
    case stringArray(allowedValues: [String])
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
}

/// Caller-owned field order/types and supplied evidence IDs. No answer values
/// or model readiness are inferred from a schema. Behavioral RED is pending.
public struct StructuredJSONSchema: Equatable, Sendable {
    public let fields: [StructuredJSONField]
    public let maximumGrammarUTF8Bytes: Int

    public init(fields: [StructuredJSONField], maximumGrammarUTF8Bytes: Int = 65_536) {
        self.fields = fields
        self.maximumGrammarUTF8Bytes = maximumGrammarUTF8Bytes
    }

    public func grammar() throws -> String { "" }
}
