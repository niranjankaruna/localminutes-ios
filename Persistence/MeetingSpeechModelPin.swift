import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// Immutable capture provenance, independent of the global Equip pointer.
/// Installation identity, full manifest and runtime profile are captured before
/// microphone/audio admission; an older meeting never guesses today's choice.
public struct StoredMeetingSpeechModelPin: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let meetingID: UUID
    public let selection: StoredModelSelection
    public init(schemaVersion: Int = 1, meetingID: UUID, selection: StoredModelSelection) {
        self.schemaVersion = schemaVersion; self.meetingID = meetingID; self.selection = selection
    }
}

public enum MeetingSpeechModelPinError: Error, Equatable, Sendable {
    case missingPin, invalidPin, immutableConflict
}

extension StoredMeetingSpeechModelPin {
    func validate() throws {
        let manifest = selection.manifest
        let hex: (String, Int) -> Bool = { value, length in
            value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        let component: (String) -> Bool = { value in
            !value.isEmpty && value.utf8.count <= 255 && value.first != "." && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || $0 == 45 || $0 == 46 || $0 == 95
            }
        }
        guard schemaVersion == 1, manifest.schemaVersion == 1, manifest.purpose == .speechRecognition,
              manifest.sampleRate == 16_000, component(manifest.modelID), hex(manifest.revision, 40),
              manifest.upstreamRepository.scheme == "https", manifest.upstreamRepository.host != nil,
              !manifest.licenseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.licenseNotice.utf8.count <= 65_536,
              selection.installationID.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw MeetingSpeechModelPinError.invalidPin
        }
        let roles = Set(manifest.artifacts.map(\.role))
        switch selection.profile {
        case .streamingZipformerONNX:
            guard roles == [.encoder, .decoder, .joiner, .tokens], manifest.artifacts.count == 4,
                  manifest.featureDimension == 80, manifest.runtimeVersion == "sherpa-onnx-1.13.8" else {
                throw MeetingSpeechModelPinError.invalidPin
            }
        case .whisperGGML:
            guard roles == [.whisper], manifest.artifacts.count == 1, manifest.featureDimension == nil,
                  manifest.runtimeVersion == "whisper.cpp-1.7.5" else { throw MeetingSpeechModelPinError.invalidPin }
        case .parakeetTDTCoreML:
            guard roles == [.coreMLAsset], (try? ParakeetModelPack.configuration(for: manifest)) != nil else {
                throw MeetingSpeechModelPinError.invalidPin
            }
        case .llamaGGUF: throw MeetingSpeechModelPinError.invalidPin
        }
        var names: Set<String> = []
        for artifact in manifest.artifacts {
            let safeName = selection.profile == .parakeetTDTCoreML
                ? artifact.fileName.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component(String($0)) }
                : component(artifact.fileName)
            guard safeName, names.insert(artifact.fileName).inserted,
                  artifact.byteCount > 0, artifact.byteCount <= 4_000_000_000, hex(artifact.sha256, 64),
                  artifact.downloadURL.scheme == "https", artifact.downloadURL.host == manifest.upstreamRepository.host,
                  artifact.downloadURL.path.contains("/resolve/\(manifest.revision)/") else {
                throw MeetingSpeechModelPinError.invalidPin
            }
        }
    }
}
