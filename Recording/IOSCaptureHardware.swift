#if os(iOS)
import AVFoundation

/// The system owns the permission prompt. Cancellation and late-grant handling
/// belong to MicrophoneCaptureRuntime before it activates any audio hardware.
@MainActor
public final class IOSCapturePermissionSource: CapturePermissionSource {
    public init() {}

    public func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

public enum IOSCaptureHardwareError: Error, Sendable, Equatable {
    case invalidState
    case inputUnavailable
}

/// MainActor owns one stable engine and its installed tap. The runtime owns the
/// callback epoch, closes admission before shutdown, and independently proves
/// callback quiescence; engine.stop/removeTap do not provide that proof here.
@MainActor
public final class IOSCaptureHardware: CaptureHardware {
    private let session: AVAudioSession
    private let engine: AVAudioEngine
    private var sessionActive = false
    private var preparedInput: AVAudioInputNode?
    private var tapInstalled = false
    private var ownsEngineResources = false

    public init() {
        session = AVAudioSession.sharedInstance()
        engine = AVAudioEngine()
    }

    public func activateSession() throws {
        guard !sessionActive, !tapInstalled, !ownsEngineResources else {
            throw IOSCaptureHardwareError.invalidState
        }
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        sessionActive = true
    }

    public func inputFormat() throws -> AVAudioFormat {
        guard sessionActive, !tapInstalled, !ownsEngineResources else {
            throw IOSCaptureHardwareError.invalidState
        }
        // No input node access or assumed preferred sample rate before the
        // session is active. The worker validates the actual PCM representation.
        let input = engine.inputNode
        guard input.numberOfOutputs > 0 else {
            throw IOSCaptureHardwareError.inputUnavailable
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0 else {
            throw IOSCaptureHardwareError.inputUnavailable
        }
        preparedInput = input
        return format
    }

    public func installTap(_ handler: @escaping CaptureTapHandler) throws {
        guard sessionActive, !tapInstalled, !ownsEngineResources,
              let input = preparedInput else {
            throw IOSCaptureHardwareError.invalidState
        }
        // Pass the stable Sendable context directly. No MainActor closure,
        // task, buffer retention, conversion or file work is introduced here.
        // The requested frame count is a hint, not a callback-size guarantee.
        input.installTap(onBus: 0, bufferSize: 2_048, format: nil, block: handler)
        tapInstalled = true
    }

    public func startEngine() throws {
        guard sessionActive, tapInstalled, !ownsEngineResources, !engine.isRunning else {
            throw IOSCaptureHardwareError.invalidState
        }
        // Keep ownership on a failed start, so runtime cleanup still calls
        // stop exactly once and releases any resources prepare allocated.
        ownsEngineResources = true
        engine.prepare()
        try engine.start()
    }

    public func stopEngine() {
        guard ownsEngineResources else { return }
        engine.stop()
        ownsEngineResources = false
    }

    public func removeTap() {
        guard tapInstalled, let input = preparedInput else { return }
        input.removeTap(onBus: 0)
        tapInstalled = false
    }

    public func deactivateSession() throws {
        guard sessionActive else { return }
        guard !ownsEngineResources, !tapInstalled else {
            throw IOSCaptureHardwareError.invalidState
        }
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
        sessionActive = false
        preparedInput = nil
    }
}
#endif
