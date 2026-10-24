import Foundation

public enum HuggingFaceRepositoryError: Error, Equatable, Sendable {
    case notImplemented, invalidRepository, invalidResponse, invalidRevision, invalidFile
    case responseTooLarge, tooManyFiles, unapprovedResponseURL, invalidLimits
    case httpStatus(Int)
}

public struct HuggingFaceRepositoryID: Equatable, Sendable {
    public let owner: String
    public let name: String
    public var rawValue: String { "\(owner)/\(name)" }

    public init(input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 256, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw HuggingFaceRepositoryError.invalidRepository
        }
        let path: String
        if text.contains("://") {
            guard let url = URLComponents(string: text), url.scheme == "https",
                  url.host?.lowercased() == "huggingface.co", url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil,
                  url.percentEncodedPath == url.path else { throw HuggingFaceRepositoryError.invalidRepository }
            let repositoryPath = String(url.path.dropFirst())
            path = repositoryPath.hasSuffix("/") ? String(repositoryPath.dropLast()) : repositoryPath
        } else { path = text }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces.allSatisfy({ Self.validComponent(String($0)) }) else {
            throw HuggingFaceRepositoryError.invalidRepository
        }
        owner = String(pieces[0]); name = String(pieces[1])
    }

    private static func validComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 96, value.first != ".",
              !value.contains(".."), value.last != "." else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
            || (97...122).contains($0) || [45, 46, 95].contains($0) }
    }
}

public struct HuggingFaceRepositoryLimits: Sendable {
    public let metadataBytes: Int
    public let cardBytes: Int
    public let configBytes: Int
    public let fileCount: Int
    public init(metadataBytes: Int = 1_048_576, cardBytes: Int = 262_144,
                configBytes: Int = 262_144, fileCount: Int = 2_048) {
        self.metadataBytes = metadataBytes; self.cardBytes = cardBytes
        self.configBytes = configBytes; self.fileCount = fileCount
    }
}

public struct HuggingFaceModelFile: Equatable, Sendable {
    public let fileName: String
    public let byteCount: Int64?
    /// An upstream-reported SHA-256, never a claim of locally verified bytes.
    public let sha256: String?
    public let downloadURL: URL
}

public enum HuggingFaceRuntimeProfile: String, Codable, Hashable, Sendable {
    case streamingZipformerONNX, whisperGGML, llamaGGUF
}

public enum HuggingFaceCompatibilityStatus: String, Equatable, Sendable {
    case notImplemented, supported, plannedRuntime, conversionRequired
    case unsupported, unverified, tooLarge, gated, selectionRequired
}

public struct HuggingFaceCompatibilityAssessment: Equatable, Sendable {
    public let status: HuggingFaceCompatibilityStatus
    public let profile: HuggingFaceRuntimeProfile?
    public let selectedFiles: [HuggingFaceModelFile]
    public let totalBytes: Int64?
    public let reasons: [String]
    public let suggestedRepositories: [String]
    public var suggestedRepository: String? { suggestedRepositories.first }
}

public struct DeviceModelResources: Equatable, Sendable {
    public let freeDiskBytes: Int64?
    public let totalMemoryBytes: Int64?
    public let availableAppMemoryBytes: Int64?
    public init(freeDiskBytes: Int64?, totalMemoryBytes: Int64?, availableAppMemoryBytes: Int64?) {
        self.freeDiskBytes = freeDiskBytes; self.totalMemoryBytes = totalMemoryBytes
        self.availableAppMemoryBytes = availableAppMemoryBytes
    }
}

public enum ModelResourceStatus: String, Equatable, Sendable {
    case notImplemented, sufficient, insufficientStorage, insufficientMemory
    case caution, unknown, contextLimitExceeded
}

public enum ModelMemoryEstimateBasis: String, Equatable, Sendable {
    case unknown, upstreamWhisperReference, weightsAndContextEstimate
}

public struct ModelResourceAssessment: Equatable, Sendable {
    public let status: ModelResourceStatus
    public let requiredDiskBytes: Int64?
    public let estimatedRAMLowerBoundBytes: Int64?
    public let estimatedRAMUpperBoundBytes: Int64?
    public let requestedContextTokens: Int
    public let maximumContextTokens: Int?
    public let estimateBasis: ModelMemoryEstimateBasis
    public let notes: [String]
}

public struct HuggingFaceContextConfiguration: Equatable, Sendable {
    public let maximumTokens: Int?
    public let hiddenSize: Int?
    public let layerCount: Int?
    public let attentionHeadCount: Int?
    public let keyValueHeadCount: Int?
}

public struct HuggingFaceModelRepository: Equatable, Sendable {
    public let id: HuggingFaceRepositoryID
    public let revision: String
    public let files: [HuggingFaceModelFile]
    public let licenseIdentifier: String?
    /// Untrusted Markdown. UI must render it as inert text or sanitize it;
    /// never execute card code/HTML or load its embedded remote images.
    public let cardMarkdown: String?
    public let pipelineTag: String?
    public let libraryName: String?
    public let modelType: String?
    public let architectures: [String]
    public let isGated: Bool
    public let contextConfiguration: HuggingFaceContextConfiguration?

    /// Format compatibility is not installed-model readiness or quality proof.
    /// Whisper GGML is a planned backend; only reviewed Qwen2/Phi3 GGUF and
    /// streaming Zipformer configurations can qualify for existing runtimes.
    public func assessment(for purpose: ModelPurpose, fileName: String? = nil,
                           maximumDownloadBytes: Int64) -> HuggingFaceCompatibilityAssessment {
        func result(_ status: HuggingFaceCompatibilityStatus, _ reason: String,
                    _ profile: HuggingFaceRuntimeProfile? = nil, _ selected: [HuggingFaceModelFile] = [],
                    _ bytes: Int64? = nil, suggestions: [String] = []) -> HuggingFaceCompatibilityAssessment {
            HuggingFaceCompatibilityAssessment(status: status, profile: profile, selectedFiles: selected,
                totalBytes: bytes, reasons: [reason], suggestedRepositories: suggestions)
        }
        guard !isGated else { return result(.gated, "This repository requires access approval; public lookup cannot install it.") }
        guard maximumDownloadBytes > 0 else { return result(.unverified, "A positive download budget is required.") }
        let type = modelType?.lowercased()
        var candidates: [HuggingFaceModelFile] = []
        var profile: HuggingFaceRuntimeProfile
        if purpose == .summary {
            profile = .llamaGGUF
            candidates = files.filter { file in
                let name = file.fileName.lowercased()
                return name.hasSuffix(".gguf") && !name.contains("mmproj")
                    && name.range(of: "-[0-9]{5}-of-[0-9]{5}\\.gguf$", options: .regularExpression) == nil
            }
        } else {
            let whisper = files.filter { Self.whisperFamily($0.fileName) != nil }
            if !whisper.isEmpty { profile = .whisperGGML; candidates = whisper }
            else {
                let isStreaming = architectures.contains { $0.lowercased().contains("streamingzipformer") }
                    || files.contains { $0.fileName.contains("chunk-") && $0.fileName.hasSuffix(".onnx") }
                guard isStreaming else {
                    if type == "whisper", files.contains(where: { $0.fileName.hasSuffix(".safetensors") }) {
                        return result(.conversionRequired, "Raw Whisper Transformers weights require conversion to a reviewed whisper.cpp GGML file; choose a converted variant from a publisher you review.", suggestions: ["ggerganov/whisper.cpp"])
                    }
                    return result(.unsupported, "No complete supported speech artifact format was found.")
                }
                profile = .streamingZipformerONNX
                let encoder = files.filter { $0.fileName.hasPrefix("encoder-") && $0.fileName.hasSuffix(".onnx") }
                let groups = encoder.compactMap { item -> [HuggingFaceModelFile]? in
                    let suffix = String(item.fileName.dropFirst("encoder-".count))
                    guard let decoder = files.first(where: { $0.fileName == "decoder-" + suffix }),
                          let joiner = files.first(where: { $0.fileName == "joiner-" + suffix }),
                          let tokens = files.first(where: { $0.fileName == "tokens.txt" }) else { return nil }
                    return [item, decoder, joiner, tokens]
                }
                let selectedGroup = fileName.flatMap { requested in groups.first { $0.contains { $0.fileName == requested } } }
                if fileName != nil, selectedGroup == nil { return result(.unsupported, "The requested file does not identify a complete streaming artifact set.") }
                guard let group = selectedGroup ?? (groups.count == 1 ? groups.first : nil) else {
                    return result(groups.count > 1 ? .selectionRequired : .unsupported,
                        "Choose one complete matching encoder, decoder, joiner and tokens set.")
                }
                candidates = group
            }
        }
        if profile != .streamingZipformerONNX {
            if let fileName {
                guard let chosen = candidates.first(where: { $0.fileName == fileName }) else {
                    return result(.unsupported, "The requested file does not match this runtime and purpose.")
                }
                candidates = [chosen]
            } else if candidates.count > 1 {
                return result(.selectionRequired, "Choose one model file; other repository variants will not be downloaded.")
            }
        }
        guard !candidates.isEmpty else { return result(.unsupported, "No supported file variant was found for this purpose.") }
        var total: Int64 = 0
        for file in candidates {
            guard let size = file.byteCount, size > 0, file.sha256 != nil else {
                return result(.unverified, "Every selected file needs a positive exact byte count and upstream SHA-256.", profile, candidates)
            }
            let addition = total.addingReportingOverflow(size)
            guard !addition.overflow else { return result(.tooLarge, "Selected file sizes overflow the supported budget.", profile, candidates) }
            total = addition.partialValue
        }
        guard total <= maximumDownloadBytes else { return result(.tooLarge, "The selected file/set exceeds the download budget.", profile, candidates, total) }
        guard let licenseIdentifier, !licenseIdentifier.isEmpty, licenseIdentifier != "other" else {
            return result(.unverified, "A usable license notice must be reviewed before installation.", profile, candidates, total)
        }
        if profile == .llamaGGUF {
            let known = ["qwen2", "phi3"].contains(type ?? "")
                || architectures.contains { ["qwen2forcausallm", "phi3forcausallm"].contains($0.lowercased()) }
            guard known else {
                return result(type == nil && architectures.isEmpty ? .unverified : .unsupported,
                    "The architecture/chat format is not verified for the current llama.cpp adapter.", profile, candidates, total)
            }
        }
        return result(profile == .whisperGGML ? .plannedRuntime : .supported,
            profile == .whisperGGML ? "Whisper GGML format identified; its runtime must pass native validation before recording can use it."
                : "Reviewed runtime format with pinned upstream metadata; actual bytes must still be verified and loaded.", profile, candidates, total)
    }

    /// Compare only the selected artifact/set against actual device facts.
    /// Estimates are guidance, never measured peak memory or admission proof.
    public func resourceAssessment(for purpose: ModelPurpose, fileName: String? = nil,
                                   contextTokens: Int = 2_048,
                                   device: DeviceModelResources) -> ModelResourceAssessment {
        let chosen = assessment(for: purpose, fileName: fileName, maximumDownloadBytes: Int64.max)
        let disk = chosen.totalBytes
        let maximum = contextConfiguration?.maximumTokens
        var lower: Int64?
        var upper: Int64?
        var basis = ModelMemoryEstimateBasis.unknown
        var notes = ["Disk is selected artifact bytes only; installation also needs staging, filesystem overhead and the recording reserve."]
        if chosen.profile == .whisperGGML, let name = chosen.selectedFiles.first?.fileName,
           let family = Self.whisperFamily(name) {
            let reference: [String: Int64] = ["tiny": 273_000_000, "base": 388_000_000,
                "small": 852_000_000, "medium": 2_100_000_000, "large": 3_900_000_000]
            lower = reference[family]; upper = lower.map { $0 + $0 / 2 }
            basis = .upstreamWhisperReference
            notes.append("Approximate upstream unquantized Whisper reference with additional planning headroom; not this quantization's measured peak, a strict bound, or a phone measurement.")
        } else if chosen.profile == .llamaGGUF, let disk, contextTokens > 0,
                  let c = contextConfiguration, let hidden = c.hiddenSize, let layers = c.layerCount,
                  let heads = c.attentionHeadCount, let kvHeads = c.keyValueHeadCount,
                  heads > 0, hidden % heads == 0, kvHeads <= heads,
                  let kv = Self.checkedProduct([2, Int64(layers), Int64(hidden / heads), Int64(kvHeads), Int64(contextTokens), 2]),
                  let minimum = Self.checkedSum([disk, kv, 134_217_728]),
                  let recommended = Self.checkedSum([minimum, max(disk / 2, 268_435_456)]) {
            lower = minimum; upper = recommended; basis = .weightsAndContextEstimate
            notes.append("Estimate: selected weights plus Float16 key/value context and workspace/headroom. Native allocation and device measurements can differ.")
        } else { notes.append("Model RAM/context requirements are unknown; file size alone is not a RAM measurement.") }
        let status: ModelResourceStatus
        if contextTokens <= 0 || maximum.map({ contextTokens > $0 }) == true { status = .contextLimitExceeded }
        else if let disk, let available = device.freeDiskBytes, available >= 0, disk > available { status = .insufficientStorage }
        else if let lower, (device.availableAppMemoryBytes.map { $0 >= 0 && lower > $0 } == true
                           || device.totalMemoryBytes.map { $0 >= 0 && lower > $0 } == true) { status = .insufficientMemory }
        else if disk == nil || lower == nil || device.freeDiskBytes == nil || device.availableAppMemoryBytes == nil
                    || device.freeDiskBytes.map({ $0 < 0 }) == true || device.availableAppMemoryBytes.map({ $0 < 0 }) == true { status = .unknown }
        else { status = .caution }
        return ModelResourceAssessment(status: status, requiredDiskBytes: disk,
            estimatedRAMLowerBoundBytes: lower, estimatedRAMUpperBoundBytes: upper,
            requestedContextTokens: contextTokens, maximumContextTokens: maximum,
            estimateBasis: basis, notes: notes)
    }

    private static func whisperFamily(_ fileName: String) -> String? {
        let name = URL(fileURLWithPath: fileName).lastPathComponent.lowercased()
        guard name.hasPrefix("ggml-"), name.hasSuffix(".bin") else { return nil }
        return ["tiny", "base", "small", "medium", "large"].first {
            let tail = name.dropFirst("ggml-".count + $0.count)
            return name.hasPrefix("ggml-" + $0) && (tail.hasPrefix(".") || tail.hasPrefix("-"))
        }
    }
    private static func checkedSum(_ values: [Int64]) -> Int64? {
        var result: Int64 = 0
        for value in values { let step = result.addingReportingOverflow(value); if step.overflow { return nil }; result = step.partialValue }
        return result
    }
    private static func checkedProduct(_ values: [Int64]) -> Int64? {
        var result: Int64 = 1
        for value in values { guard value > 0 else { return nil }; let step = result.multipliedReportingOverflow(by: value); if step.overflow { return nil }; result = step.partialValue }
        return result
    }
}

/// Public, unauthenticated metadata only. No weights, remote code, tokens,
/// browser cookies or model-card embedded resources may be fetched here.
public actor HuggingFaceRepositoryService {
    private let configuration: URLSessionConfiguration
    private let limits: HuggingFaceRepositoryLimits
    public init(configuration: URLSessionConfiguration = .ephemeral,
                limits: HuggingFaceRepositoryLimits = .init()) {
        let options = configuration.copy() as! URLSessionConfiguration
        options.httpShouldSetCookies = false; options.httpCookieStorage = nil
        options.urlCredentialStorage = nil; options.httpAdditionalHeaders = [:]; options.urlCache = nil
        options.requestCachePolicy = .reloadIgnoringLocalCacheData
        options.timeoutIntervalForRequest = 30; options.timeoutIntervalForResource = 45
        self.configuration = options; self.limits = limits
    }

    public func inspect(_ input: String) async throws -> HuggingFaceModelRepository {
        let id = try HuggingFaceRepositoryID(input: input)
        guard limits.metadataBytes > 0, limits.metadataBytes <= 1_048_576,
              limits.cardBytes > 0, limits.cardBytes <= 262_144,
              limits.configBytes > 0, limits.configBytes <= 262_144,
              limits.fileCount > 0, limits.fileCount <= 2_048 else { throw HuggingFaceRepositoryError.invalidLimits }
        try Task.checkCancellation()
        let metadataURL = URL(string: "https://huggingface.co/api/models/\(id.rawValue)?blobs=true")!
        let metadata = try await read(metadataURL, cap: limits.metadataBytes)
        guard let object = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let identity = object["id"] as? String,
              identity.lowercased() == id.rawValue.lowercased() else { throw HuggingFaceRepositoryError.invalidResponse }
        guard let revision = object["sha"] as? String, Self.hex(revision, count: 40) else {
            throw HuggingFaceRepositoryError.invalidRevision
        }
        guard let entries = object["siblings"] as? [[String: Any]] else { throw HuggingFaceRepositoryError.invalidResponse }
        guard entries.count <= limits.fileCount else { throw HuggingFaceRepositoryError.tooManyFiles }
        var seen = Set<String>()
        let files = try entries.map { entry -> HuggingFaceModelFile in
            guard let name = entry["rfilename"] as? String, Self.safeFile(name), seen.insert(name).inserted else {
                throw HuggingFaceRepositoryError.invalidFile
            }
            let size = try Self.fileSize(entry["size"])
            if let raw = entry["lfs"], !(raw is NSNull), !(raw is [String: Any]) {
                throw HuggingFaceRepositoryError.invalidFile
            }
            let lfs = entry["lfs"] as? [String: Any]
            let lfsSize = try Self.fileSize(lfs?["size"])
            if let size, let lfsSize, size != lfsSize { throw HuggingFaceRepositoryError.invalidFile }
            let digest = lfs?["sha256"] as? String
            if let raw = lfs?["sha256"], !(raw is NSNull), (digest == nil || !Self.hex(digest!, count: 64)) {
                throw HuggingFaceRepositoryError.invalidFile
            }
            return HuggingFaceModelFile(fileName: name, byteCount: size ?? lfsSize, sha256: digest,
                downloadURL: URL(string: "https://huggingface.co/\(id.rawValue)/resolve/\(revision)/\(name)")!)
        }
        let gate = object["gated"]
        let gated = (gate as? Bool ?? false) || (gate is String && (gate as? String) != "false")
            || (object["private"] as? Bool ?? false)
        let license = (object["cardData"] as? [String: Any])?["license"] as? String
        let pipeline = Self.text(object["pipeline_tag"])
        let library = Self.text(object["library_name"])
        var card: String?
        var config: [String: Any] = [:]
        if !gated {
            if let bytes = try await optionalRead(URL(string: "https://huggingface.co/\(id.rawValue)/resolve/\(revision)/README.md")!, cap: limits.cardBytes) {
                guard let text = String(data: bytes, encoding: .utf8) else { throw HuggingFaceRepositoryError.invalidResponse }
                card = text
            }
            if let bytes = try await optionalRead(URL(string: "https://huggingface.co/\(id.rawValue)/resolve/\(revision)/config.json")!, cap: limits.configBytes) {
                guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw HuggingFaceRepositoryError.invalidResponse }
                config = parsed
            }
        }
        let gguf = object["gguf"] as? [String: Any] ?? [:]
        let modelType = Self.text(config["model_type"]) ?? Self.text(gguf["architecture"])
        let architectures = config["architectures"] as? [String] ?? []
        guard architectures.count <= 64, architectures.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            throw HuggingFaceRepositoryError.invalidResponse
        }
        let context = HuggingFaceContextConfiguration(
            maximumTokens: Self.positive(config["max_position_embeddings"]) ?? Self.positive(gguf["context_length"]),
            hiddenSize: Self.positive(config["hidden_size"]) ?? Self.positive(gguf["embedding_length"]),
            layerCount: Self.positive(config["num_hidden_layers"]) ?? Self.positive(gguf["block_count"]),
            attentionHeadCount: Self.positive(config["num_attention_heads"]),
            keyValueHeadCount: Self.positive(config["num_key_value_heads"]) ?? Self.positive(config["num_attention_heads"]))
        try Task.checkCancellation()
        return HuggingFaceModelRepository(id: id, revision: revision, files: files,
            licenseIdentifier: Self.text(license), cardMarkdown: card, pipelineTag: pipeline, libraryName: library,
            modelType: modelType, architectures: architectures, isGated: gated,
            contextConfiguration: gated ? nil : context)
    }

    private func read(_ url: URL, cap: Int) async throws -> Data {
        let request = HFBoundedMetadataRequest(configuration: configuration, url: url, limit: cap)
        return try await request.perform()
    }
    private func optionalRead(_ url: URL, cap: Int) async throws -> Data? {
        do { return try await read(url, cap: cap) }
        catch HuggingFaceRepositoryError.httpStatus(404) { return nil }
    }
    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func safeFile(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 512 else { return false }
        let pieces = name.split(separator: "/", omittingEmptySubsequences: false)
        return pieces.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.utf8.count <= 255
                && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || [45, 46, 95].contains($0) }
        }
    }
    private static func fileSize(_ value: Any?) throws -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
              let size = Int64(number.stringValue), size >= 0 else { throw HuggingFaceRepositoryError.invalidFile }
        return size
    }
    private static func positive(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, String(cString: value.objCType) != "c",
              let count = Int(value.stringValue), count > 0, count <= 16_777_216 else { return nil }
        return count
    }
    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= 256,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }
}

/// URLSession invokes delegates off the actor. The lock protects the complete
/// continuation/task/buffer lifecycle; no response can allocate an unbounded
/// accumulator, follow a foreign redirect, or resume a continuation twice.
private final class HFBoundedMetadataRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let limit: Int
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Data, Error>?
    private var outcome: Result<Data, Error>?
    private var buffer = Data()
    private var accepted = false
    private var redirects = 0

    init(configuration: URLSessionConfiguration, url: URL, limit: Int) {
        self.url = url; self.limit = limit
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func perform() async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { pending in
                let next: URLSessionDataTask? = lock.withLock {
                    if let outcome { pending.resume(with: outcome); return nil }
                    continuation = pending
                    var request = URLRequest(url: url)
                    request.httpShouldHandleCookies = false
                    request.setValue("application/json, text/plain;q=0.9", forHTTPHeaderField: "Accept")
                    task = session?.dataTask(with: request)
                    return task
                }
                next?.resume()
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, validRoute(finalURL) else {
            finish(.failure(HuggingFaceRepositoryError.unapprovedResponseURL)); completionHandler(.cancel); return
        }
        guard http.statusCode == 200 else {
            finish(.failure(HuggingFaceRepositoryError.httpStatus(http.statusCode))); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            finish(.failure(HuggingFaceRepositoryError.responseTooLarge)); completionHandler(.cancel); return
        }
        let alive = lock.withLock { () -> Bool in
            guard outcome == nil else { return false }; accepted = true; return true
        }
        completionHandler(alive ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let tooLarge = lock.withLock { () -> Bool in
            guard outcome == nil, accepted else { return false }
            guard data.count <= limit - buffer.count else { return true }
            buffer.append(data); return false
        }
        if tooLarge { finish(.failure(HuggingFaceRepositoryError.responseTooLarge)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        let result = lock.withLock { accepted ? Result<Data, Error>.success(buffer)
            : .failure(HuggingFaceRepositoryError.invalidResponse) }
        finish(result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let target = request.url, validRoute(target), request.httpMethod == "GET" else {
            finish(.failure(HuggingFaceRepositoryError.unapprovedResponseURL)); completionHandler(nil); return
        }
        let approved = lock.withLock { () -> Bool in
            guard outcome == nil, redirects < 5 else { return false }; redirects += 1; return true
        }
        guard approved else { finish(.failure(HuggingFaceRepositoryError.unapprovedResponseURL)); completionHandler(nil); return }
        var clean = URLRequest(url: target)
        clean.httpShouldHandleCookies = false
        completionHandler(clean)
    }

    private func validRoute(_ target: URL) -> Bool {
        guard target.scheme == "https", target.host?.lowercased() == "huggingface.co",
              target.user == nil, target.password == nil, target.port == nil || target.port == 443,
              target.fragment == nil else { return false }
        if target.path == url.path { return true }
        let pieces = url.path.split(separator: "/")
        guard let resolve = pieces.firstIndex(of: "resolve"), resolve + 1 < pieces.count else { return false }
        let revision = pieces[resolve + 1]
        return target.path.hasPrefix("/api/resolve-cache/models/\(pieces[0])/\(pieces[1])/\(revision)/")
            && target.lastPathComponent == url.lastPathComponent
    }

    private func finish(_ result: Result<Data, Error>) {
        let held: (CheckedContinuation<Data, Error>?, URLSessionDataTask?, URLSession?) = lock.withLock {
            guard outcome == nil else { return (nil, nil, nil) }
            outcome = result
            let held = (continuation, task, session)
            continuation = nil; task = nil; session = nil
            return held
        }
        held.0?.resume(with: result)
        held.1?.cancel(); held.2?.invalidateAndCancel()
    }
}
