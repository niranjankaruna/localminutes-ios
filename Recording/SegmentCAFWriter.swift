import AVFoundation
import AudioToolbox
import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

public enum SegmentWriterError: Error, Equatable {
    case invalidConfiguration, directoryNotEmpty, formatMismatch, finished, ioFailed
}

public struct StoredAudioSegment: Codable, Equatable, Sendable {
    public let relativePath: String
    public let startFrame: Int64
    public let frameCount: Int64
}

public struct AudioCaptureManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sessionID: UUID
    public let totalFrames: Int64
    public let segments: [StoredAudioSegment]
}

/// Serial conversion-worker ownership. Capture never waits for file I/O.
/// Only closed, synchronized segments are published in the atomic checkpoint.
/// Reconciliation of incomplete files after termination belongs to T08 recovery.
public final class SegmentCAFWriter {
    private let directory: URL
    private let sessionID: UUID
    private let maximumSegmentFrames: Int64
    private let scratch: AVAudioPCMBuffer
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var currentFrames: Int64 = 0
    private var totalFrames: Int64 = 0
    private var segments: [StoredAudioSegment] = []
    private var finalManifest: AudioCaptureManifest?
    private var failed = false

    public init(directory: URL, sessionID: UUID, maximumSegmentFrames: Int64 = 960_000) throws {
        guard directory.isFileURL, maximumSegmentFrames > 0,
              maximumSegmentFrames <= 960_000,
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(min(maximumSegmentFrames, 16_384))) else {
            throw SegmentWriterError.invalidConfiguration
        }
        self.directory = directory.standardizedFileURL
        self.sessionID = sessionID
        self.maximumSegmentFrames = maximumSegmentFrames
        self.scratch = scratch
        do {
            try Self.preflightDirectory(self.directory)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: self.directory.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw SegmentWriterError.ioFailed }
                guard try FileManager.default.contentsOfDirectory(atPath: self.directory.path).isEmpty else {
                    throw SegmentWriterError.directoryNotEmpty
                }
            } else {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            try PersistentFilePolicy.protectDirectory(self.directory)
        } catch let error as SegmentWriterError { throw error }
        catch { throw SegmentWriterError.ioFailed }
    }

    /// Only OS-provided support/temp boundaries may contain recording storage.
    /// Trust the OS boundary's canonical alias (for example /var on Darwin),
    /// then inspect every caller-owned component before any mkdir can follow a
    /// link and create files outside that boundary.
    private static func preflightDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        let osRoots = [manager.temporaryDirectory] +
            manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let roots = osRoots.flatMap { root in
            [root.standardizedFileURL, root.resolvingSymlinksInPath().standardizedFileURL]
        }
        guard let root = roots.filter({ directory.path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }) else {
            throw SegmentWriterError.ioFailed
        }
        let suffix = directory.pathComponents.dropFirst(root.pathComponents.count)
        var current = root
        for component in suffix {
            current.appendPathComponent(component)
            do {
                let attributes = try manager.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw SegmentWriterError.ioFailed
                }
            } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
                // A missing component is allowed only after all existing
                // ancestors have been inspected; creation happens afterwards.
            }
        }
        let expected = suffix.reduce(root.resolvingSymlinksInPath().standardizedFileURL) {
            $0.appendingPathComponent($1)
        }.standardizedFileURL
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == expected.path else {
            throw SegmentWriterError.ioFailed
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) throws {
        guard finalManifest == nil else { throw SegmentWriterError.finished }
        guard !failed else { throw SegmentWriterError.ioFailed }
        guard buffer.format.sampleRate == 16_000, buffer.format.channelCount == 1,
              buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else {
            throw SegmentWriterError.formatMismatch
        }
        guard buffer.frameLength > 0 else { return }
        guard let samples = buffer.floatChannelData?[0], let destination = scratch.floatChannelData?[0] else {
            throw SegmentWriterError.formatMismatch
        }
        do {
            var offset = 0
            while offset < Int(buffer.frameLength) {
                if file == nil { try openSegment() }
                let count = min(min(Int(buffer.frameLength) - offset, Int(maximumSegmentFrames - currentFrames)), Int(scratch.frameCapacity))
                let (newTotal, overflow) = totalFrames.addingReportingOverflow(Int64(count))
                guard count > 0, !overflow, let file else { throw SegmentWriterError.ioFailed }
                destination.update(from: samples.advanced(by: offset), count: count)
                scratch.frameLength = AVAudioFrameCount(count)
                try file.write(from: scratch)
                currentFrames += Int64(count)
                totalFrames = newTotal
                offset += count
                if currentFrames == maximumSegmentFrames { try closeSegment() }
            }
        } catch {
            failed = true
            throw SegmentWriterError.ioFailed
        }
    }

    public func finish() throws -> AudioCaptureManifest {
        if let finalManifest { return finalManifest }
        guard !failed else { throw SegmentWriterError.ioFailed }
        do {
            if file != nil { try closeSegment() }
            let manifest = makeManifest()
            try persist(manifest)
            finalManifest = manifest
            return manifest
        } catch {
            failed = true
            throw SegmentWriterError.ioFailed
        }
    }

    private func openSegment() throws {
        let name = String(format: "segment-%06d.caf", segments.count)
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw SegmentWriterError.ioFailed }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        fileURL = url
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try PersistentFilePolicy.protectItem(url, within: directory)
    }

    private func closeSegment() throws {
        guard let file, let fileURL, currentFrames > 0 else { throw SegmentWriterError.ioFailed }
        // iOS18/macOS15 close updates CAF headers before another reader sees it.
        file.close()
        self.file = nil
        try synchronize(fileURL)
        segments.append(StoredAudioSegment(relativePath: fileURL.lastPathComponent,
            startFrame: totalFrames - currentFrames, frameCount: currentFrames))
        currentFrames = 0
        self.fileURL = nil
        try persist(makeManifest())
    }

    private func makeManifest() -> AudioCaptureManifest {
        let durableFrames = segments.last.map { $0.startFrame + $0.frameCount } ?? 0
        return AudioCaptureManifest(schemaVersion: 1, sessionID: sessionID,
                                    totalFrames: durableFrames, segments: segments)
    }

    private func persist(_ manifest: AudioCaptureManifest) throws {
        let url = directory.appendingPathComponent("capture-manifest.json")
        let data = try JSONEncoder().encode(manifest)
        try PersistentFilePolicy.writeAtomically(data, to: url, within: directory)
        try synchronize(url)
    }

    private func synchronize(_ url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}
