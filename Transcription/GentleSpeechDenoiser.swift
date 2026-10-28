import Accelerate
import Foundation

public enum SpeechNoiseReduction: String, Equatable, Sendable {
    case off, gentle
}

/// Owned only by the speech adapter's serial worker. Processes a copy of each
/// unpadded 16 kHz window; capture files and source sample offsets never change.
/// This is conservative stationary-noise reduction, not speaker separation.
final class GentleSpeechDenoiser {
    static let frameSize = 512 // 32 ms at 16 kHz.
    static let hopSize = 256
    static let minimumGain: Float = 0.7079458 // At most 3 dB reduction per bin.
    private static let bins = GentleSpeechDenoiser.frameSize / 2 + 1
    private static let bucketFrames = 32
    private static let historyBuckets = 3

    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup
    private let window: [Float]
    private var timeReal = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private let timeImaginary = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private var frequencyReal = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private var frequencyImaginary = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private var inverseReal = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private var inverseImaginary = [Float](repeating: 0, count: GentleSpeechDenoiser.frameSize)
    private var power = [Float](repeating: 0, count: GentleSpeechDenoiser.bins)
    private var smoothedPower = [Float](repeating: 0, count: GentleSpeechDenoiser.bins)
    private var bucketMinimum = [Float](repeating: .infinity, count: GentleSpeechDenoiser.bins)
    private var history: [[Float]] = []
    private var historyCursor = 0
    private var bucketCount = 0
    private var hasPower = false
    private var gains = [Float](repeating: 1, count: GentleSpeechDenoiser.bins)
    private var desiredGains = [Float](repeating: 1, count: GentleSpeechDenoiser.bins)

    /// Setup failure bypasses enhancement rather than making recording fail.
    init?() {
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.frameSize), .FORWARD) else {
            return nil
        }
        guard let inverse = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.frameSize), .INVERSE) else {
            vDSP_DFT_DestroySetup(forward)
            return nil
        }
        self.forward = forward
        self.inverse = inverse
        let count = Self.frameSize
        window = (0..<count).map {
            Float(sqrt(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(count))))
        }
    }

    deinit {
        vDSP_DFT_DestroySetup(forward)
        vDSP_DFT_DestroySetup(inverse)
    }

    func reset() {
        history.removeAll(keepingCapacity: true)
        historyCursor = 0
        bucketCount = 0
        hasPower = false
        for bin in 0..<Self.bins {
            smoothedPower[bin] = 0
            bucketMinimum[bin] = .infinity
            gains[bin] = 1
            desiredGains[bin] = 1
        }
    }

    func process(_ samples: [Float], isCancelled: () -> Bool = { false }) throws -> [Float] {
        guard samples.count <= ParakeetSpeechAdapter.stepSamples,
              samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
            throw SpeechRecognitionError.invalidSamples
        }
        if isCancelled() { throw CancellationError() }
        // Tiny final tails contain too little information for a noise estimate.
        guard samples.count >= Self.frameSize else { return samples }
        var output = [Float](repeating: 0, count: samples.count)
        var weights = [Float](repeating: 0, count: samples.count)

        // Centered, overlapping frames include both edges. Zero padding belongs
        // only to the transform: it neither trains the floor nor shifts audio.
        for start in stride(from: -Self.hopSize, to: samples.count, by: Self.hopSize) {
            if isCancelled() { throw CancellationError() }
            for index in 0..<Self.frameSize {
                let source = start + index
                timeReal[index] = samples.indices.contains(source) ? samples[source] * window[index] : 0
            }
            vDSP_DFT_Execute(forward, timeReal, timeImaginary, &frequencyReal, &frequencyImaginary)
            for bin in 0..<Self.bins {
                power[bin] = frequencyReal[bin] * frequencyReal[bin]
                    + frequencyImaginary[bin] * frequencyImaginary[bin]
            }
            if start >= 0, start + Self.frameSize <= samples.count { observeNoiseFloor() }
            updateGains()
            for bin in 0..<Self.frameSize {
                let gain = gains[min(bin, Self.frameSize - bin)]
                frequencyReal[bin] *= gain
                frequencyImaginary[bin] *= gain
            }
            vDSP_DFT_Execute(inverse, frequencyReal, frequencyImaginary, &inverseReal, &inverseImaginary)
            for index in 0..<Self.frameSize {
                let destination = start + index
                guard samples.indices.contains(destination) else { continue }
                output[destination] += inverseReal[index] / Float(Self.frameSize) * window[index]
                weights[destination] += window[index] * window[index]
            }
        }
        for index in output.indices { output[index] /= weights[index] }
        // Spectral filtering can overshoot at transients. Preserve the original
        // window if that happens; never hard-clip or normalize quiet speech down.
        guard output.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { return samples }
        return output
    }

    private func observeNoiseFloor() {
        // A real pause or sudden drop in room level must lower the estimate
        // promptly. Otherwise smoothed energy from preceding speech leaks into
        // the noise floor and can unnecessarily soften the next faint consonant.
        // This only updates the estimate; no sample is gated or classified away.
        let levelDropped = hasPower && power.reduce(0, +) < 0.1 * smoothedPower.reduce(0, +)
        for bin in 0..<Self.bins {
            smoothedPower[bin] = hasPower && !levelDropped
                ? 0.8 * smoothedPower[bin] + 0.2 * power[bin] : power[bin]
            bucketMinimum[bin] = min(bucketMinimum[bin], smoothedPower[bin])
        }
        hasPower = true
        bucketCount += 1
        guard bucketCount == Self.bucketFrames else { return }
        // Rolling minima, rather than an initial "silence" recording, avoid
        // requiring the user to pause before speaking. History is about 1.5 s.
        if history.count < Self.historyBuckets { history.append(bucketMinimum) }
        else {
            history[historyCursor] = bucketMinimum
            historyCursor = (historyCursor + 1) % Self.historyBuckets
        }
        bucketCount = 0
        for bin in 0..<Self.bins { bucketMinimum[bin] = .infinity }
    }

    private func updateGains() {
        for bin in 0..<Self.bins {
            var floor: Float = .infinity
            for bucket in history { floor = min(floor, bucket[bin]) }
            if floor.isFinite, power[bin] > 0 {
                // Underestimate the floor to favor retaining speech. Never gate
                // a bin or discard a window, even when speech is below noise.
                let remaining = max(0, 1 - 0.8 * floor / power[bin])
                desiredGains[bin] = max(Self.minimumGain, sqrt(remaining))
            } else { desiredGains[bin] = 1 }
        }
        for bin in 0..<Self.bins {
            // Frequency smoothing avoids isolated notches ("musical noise").
            let target = 0.25 * desiredGains[max(0, bin - 1)] + 0.5 * desiredGains[bin]
                + 0.25 * desiredGains[min(Self.bins - 1, bin + 1)]
            // Restore speech onsets quickly; introduce attenuation gradually.
            let rate: Float = target > gains[bin] ? 0.8 : 0.15
            gains[bin] = min(1, max(Self.minimumGain, gains[bin] + rate * (target - gains[bin])))
        }
    }
}
