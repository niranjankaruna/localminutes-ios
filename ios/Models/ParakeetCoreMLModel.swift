import Foundation

/// Exact NVIDIA Parakeet TDT v2 Core ML conversion. Nested asset paths are
/// data, not executable model-card instructions. Hash provenance is preserved.
public enum ParakeetCoreMLModel {
    public static let repositoryID = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public static let revision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
    public static let runtimeVersion = "coreml-parakeet-tdt-v2-fluid-c79c4106"
    public static let runtimeSourceCommit = "c79c4106b954f81205113c3343e5a7e59a1089b5"
    public static let totalDownloadBytes: Int64 = 464_413_247
    public static let manifest = ModelManifest(
        modelID: "parakeet-tdt-0-6b-v2-coreml", purpose: .speechRecognition,
        upstreamRepository: URL(string: "https://huggingface.co/" + repositoryID)!,
        revision: revision, licenseIdentifier: "CC-BY-4.0",
        licenseNotice: "NVIDIA Parakeet TDT 0.6B v2; Core ML conversion by FluidInference. This is an adapted Core ML representation of https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2. Model license: https://creativecommons.org/licenses/by/4.0/. Swift decoder source: FluidInference/FluidAudio at c79c4106b954f81205113c3343e5a7e59a1089b5, Apache-2.0: https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/LICENSE. Preserve the upstream model attribution and Apache license notices.",
        runtimeVersion: runtimeVersion, sampleRate: 16_000, featureDimension: 128,
        artifacts: [
            asset("Decoder.mlmodelc/analytics/coremldata.bin", 243,
                  "46de1a6fe2e49d19a2125bc91acf020df7f2aea84ba821532aade8427a440b05", .upstreamReported),
            asset("Decoder.mlmodelc/coremldata.bin", 554,
                  "d200ca07694a347f6d02a3886a062ae839831e094e443222f2e48a14945966a8", .upstreamReported),
            asset("Decoder.mlmodelc/metadata.json", 3427,
                  "90a279b822496316458febc0ce761ab05954fadd9d66aa97bea077a35fc8f2b2", .independentlyDownloaded),
            asset("Decoder.mlmodelc/model.mil", 13106,
                  "7b95a5a6b672c652000348a67b6d4d92bb8e176b978c6666fe73c28a4d7ec579", .independentlyDownloaded),
            asset("Decoder.mlmodelc/weights/weight.bin", 14429952,
                  "27d26890221d82322c1092fd99d7b40578e435d5cf4b83c887c42603caf97aba", .upstreamReported),
            asset("Encoder.mlmodelc/analytics/coremldata.bin", 243,
                  "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105", .upstreamReported),
            asset("Encoder.mlmodelc/coremldata.bin", 485,
                  "4def7aa848599ad0e17a8b9a982edcdbf33cf92e1f4b798de32e2ca0bc74b030", .upstreamReported),
            asset("Encoder.mlmodelc/metadata.json", 2926,
                  "58222fbc48c13c49d9715567803cd50cb9c23e4360462e0f8ffcea59a2c73c63", .independentlyDownloaded),
            asset("Encoder.mlmodelc/model.mil", 959769,
                  "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808", .independentlyDownloaded),
            asset("Encoder.mlmodelc/weights/weight.bin", 445187200,
                  "4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e", .upstreamReported),
            asset("JointDecision.mlmodelc/analytics/coremldata.bin", 243,
                  "f1183ba213bb94a918c8d2cad19ab045320618f97f6ca662245b3936d7b090f7", .upstreamReported),
            asset("JointDecision.mlmodelc/coremldata.bin", 534,
                  "e2c6752f1c8cf2d3f6f26ec93195c9bfa759ad59edf9f806696a138154f96f11", .upstreamReported),
            asset("JointDecision.mlmodelc/metadata.json", 2936,
                  "ba8d309417b9acd4a175fdb15687de6a941db2f5b06666a60e7cf3cc8e2d3c3c", .independentlyDownloaded),
            asset("JointDecision.mlmodelc/model.mil", 9722,
                  "93bf82042235127cb81ab537dcae47a1c2e7e242ce4ffdaf772981b45eedc4f0", .independentlyDownloaded),
            asset("JointDecision.mlmodelc/weights/weight.bin", 3453388,
                  "ca22a65903a05e64137677da608077578a8606090a598abf4875fa6199aaa19d", .upstreamReported),
            asset("Preprocessor.mlmodelc/analytics/coremldata.bin", 243,
                  "03ab3c1327a054c54c07a40325db967ec574f2c91dcc8192bfa44aa561bcf2d8", .upstreamReported),
            asset("Preprocessor.mlmodelc/coremldata.bin", 494,
                  "d88ea1fc349459c9e100d6a96688c5b29a1f0d865f544be103001724b986b6d6", .upstreamReported),
            asset("Preprocessor.mlmodelc/metadata.json", 2974,
                  "fb16c581ff5e1b962e7cb2181ed892cd32f9f84c12b6e80ff3e089f28e35bcbb", .independentlyDownloaded),
            asset("Preprocessor.mlmodelc/model.mil", 27166,
                  "3e06d16fd061294c8a75be68c43a3b1ed1f593d4a9c35249e9cdbccadc59721e", .independentlyDownloaded),
            asset("Preprocessor.mlmodelc/weights/weight.bin", 298880,
                  "a5f7df6c7f47147ae9486fe18cc7792f9a44d093ec3c6a11e91ef2dc363c48dc", .upstreamReported),
            asset("parakeet_vocab.json", 18762,
                  "57019fe3c745772ca83a1b048a4bb951cd51329504ea33d4d83316b96e279a97", .independentlyDownloaded)
        ])

    private static func asset(_ name: String, _ bytes: Int64, _ sha256: String,
                              _ provenance: ModelDigestProvenance) -> ModelArtifact {
        .init(role: .coreMLAsset, fileName: name, byteCount: bytes, sha256: sha256,
              downloadURL: URL(string: "https://huggingface.co/" + repositoryID + "/resolve/" + revision + "/" + name)!,
              digestProvenance: provenance)
    }
}
