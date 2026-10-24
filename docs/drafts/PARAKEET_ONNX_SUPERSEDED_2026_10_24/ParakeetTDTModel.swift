import Foundation

/// Reviewed immutable conversion of NVIDIA Parakeet TDT 0.6B v2. The original
/// NeMo checkpoint is not directly loadable by the bundled sherpa runtime.
/// Weight digests are publisher-reported until an installation verifies bytes.
public enum ParakeetTDTModel {
    public static let repositoryID = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
    public static let revision = "1ab9323565ddb038682214b292f588070a538ce2"
    public static let manifest = ModelManifest(
        modelID: "sherpa-parakeet-tdt-0.6b-v2-int8", purpose: .speechRecognition,
        upstreamRepository: URL(string: "https://huggingface.co/" + repositoryID)!,
        revision: revision, licenseIdentifier: "CC-BY-4.0",
        licenseNotice: "NVIDIA Parakeet TDT 0.6B v2; ONNX int8 conversion by sherpa-onnx/csukuangfj. CC-BY-4.0: https://creativecommons.org/licenses/by/4.0/. Source model: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2. Preserve attribution and identify the ONNX conversion.",
        runtimeVersion: "sherpa-onnx-1.13.8", sampleRate: 16_000, featureDimension: 80,
        artifacts: [
            artifact(.encoder, "encoder.int8.onnx", 652_184_296,
                     "a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab"),
            artifact(.decoder, "decoder.int8.onnx", 7_257_753,
                     "b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e"),
            artifact(.joiner, "joiner.int8.onnx", 1_739_080,
                     "7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2"),
            artifact(.tokens, "tokens.txt", 9_384,
                     "ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d",
                     provenance: .independentlyDownloaded)
        ])

    private static func artifact(_ role: ModelFileRole, _ name: String, _ bytes: Int64,
                                 _ digest: String,
                                 provenance: ModelDigestProvenance = .upstreamReported) -> ModelArtifact {
        .init(role: role, fileName: name, byteCount: bytes, sha256: digest,
              downloadURL: URL(string: "https://huggingface.co/" + repositoryID + "/resolve/" + revision + "/" + name)!,
              digestProvenance: provenance)
    }
}
