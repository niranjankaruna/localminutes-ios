import CoreML
import FluidAudio
import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// The model pack supplies immutable artifacts and a decoder contract. The
/// adapter supplies executable decoding logic; model names never choose it.
enum ParakeetModelAdapter {
    static func load(directory: URL, manifest: ModelManifest,
                     configuration: MLModelConfiguration) throws -> AsrModels {
        let pack = try ParakeetModelPack.configuration(for: manifest)
        let version: AsrModelVersion
        switch pack.decoderContract {
        case "parakeet-tdt-v2": version = .v2
        case "parakeet-tdt-v3": version = .v3
        default: throw ParakeetModelPackError.unsupportedContract
        }
        guard let precision = ParakeetEncoderPrecision(rawValue: pack.encoderPrecision) else {
            throw SpeechRecognitionError.invalidModel
        }
        let models = try AsrModels.loadLocal(from: directory, version: version,
            configuration: configuration, encoderPrecision: precision)
        // Inspect actual loaded Core ML descriptions, independently of the
        // pack's untrusted declaration, before constructing a TDT manager.
        try require(models.preprocessor, inputs: ["audio_signal", "audio_length"], outputs: ["mel", "mel_length"])
        guard let encoder = models.encoder else { throw SpeechRecognitionError.invalidModel }
        try require(encoder, inputs: ["mel", "mel_length"], outputs: ["encoder", "encoder_length"])
        try require(models.decoder, inputs: ["targets", "target_length", "h_in", "c_in"], outputs: ["decoder", "h_out", "c_out"])
        try require(models.joint, inputs: ["encoder_step", "decoder_step"],
            outputs: pack.decoderContract == "parakeet-tdt-v3"
                ? ["token_id", "token_prob", "duration", "top_k_ids", "top_k_logits"]
                : ["token_id", "token_prob", "duration"])
        for name in ["h_in", "c_in"] {
            guard let shape = models.decoder.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint?.shape,
                  shape.map(\.intValue) == [2, 1, 640] else { throw SpeechRecognitionError.invalidModel }
        }
        return models
    }

    private static func require(_ model: MLModel, inputs: Set<String>, outputs: Set<String>) throws {
        let description = model.modelDescription
        guard Set(description.inputDescriptionsByName.keys) == inputs,
              outputs.isSubset(of: Set(description.outputDescriptionsByName.keys)),
              description.inputDescriptionsByName.values.allSatisfy({ $0.type == .multiArray }),
              outputs.allSatisfy({ description.outputDescriptionsByName[$0]?.type == .multiArray }) else {
            throw SpeechRecognitionError.invalidModel
        }
    }
}
