import Foundation

public struct ParakeetModelConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let decoderContract: String
    public let encoderPrecision: String
    public init(schemaVersion: Int = 1, decoderContract: String, encoderPrecision: String = "int8") {
        self.schemaVersion = schemaVersion; self.decoderContract = decoderContract
        self.encoderPrecision = encoderPrecision
    }
}

public enum ParakeetModelPackError: Error, Equatable, Sendable {
    case notImplemented, unsupportedContract, invalidManifest
}

public enum ParakeetModelPack {
    public static let runtimeVersion = "coreml-parakeet-tdt-fluid-c79c4106"
    // Compileable interfaces only; actual contract behavior awaits hosted RED.
    public static func decode(_ data: Data) throws -> ModelManifest {
        throw ParakeetModelPackError.notImplemented
    }
    public static func configuration(for manifest: ModelManifest) throws -> ParakeetModelConfiguration {
        throw ParakeetModelPackError.notImplemented
    }
}
