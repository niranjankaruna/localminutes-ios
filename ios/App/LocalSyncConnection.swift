#if os(iOS)
import Foundation
@preconcurrency import Network
import Security
import CryptoKit

struct LocalSyncInvitation: Codable, Sendable {
    let version: Int
    let host: String
    let port: UInt16
    let fingerprint: String
    let token: String
    let replicaId: String
    let name: String

    func validated() throws -> Self {
        _ = try LocalSyncArchive.canonicalID(replicaId)
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard version == 1, parts.count == 4, host.split(separator: ".", omittingEmptySubsequences: false).count == 4,
              parts.map(String.init).joined(separator: ".") == host, port > 0, name.utf8.count <= 320,
              parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254),
              fingerprint.count == 64, token.count == 64,
              (fingerprint + token).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw LocalSyncError.invalidData }
        return self
    }
}

private final class LocalSyncReady: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    init(_ continuation: CheckedContinuation<Void, any Error>) { self.continuation = continuation }
    func finish(_ result: Result<Void, any Error>) {
        lock.lock(); let value = continuation; continuation = nil; lock.unlock()
        value?.resume(with: result)
    }
}

/// The NWConnection callbacks are thread safe; one controller serializes protocol exchanges.
final class LocalSyncConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    init(invitation: LocalSyncInvitation, service: LocalSyncDiscoveredService? = nil) throws {
        _ = try invitation.validated()
        let transportQueue = DispatchQueue(label: "LocalMinutes.LocalSync")
        queue = transportQueue
        let tls = NWProtocolTLS.Options()
        let expected = invitation.fingerprint
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let native = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let certificates = SecTrustCopyCertificateChain(native) as? [SecCertificate], let leaf = certificates.first else { complete(false); return }
            let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            // A first-pairing QR supplies the exact leaf fingerprint. Unknown or changed identities are never accepted.
            complete(digest == expected)
        }, transportQueue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.prohibitedInterfaceTypes = [.cellular, .loopback]
        if let service {
            connection = NWConnection(to: .service(name: service.name, type: "_localminutes._tcp", domain: "local.", interface: nil), using: parameters)
        } else {
            connection = NWConnection(host: NWEndpoint.Host(invitation.host), port: NWEndpoint.Port(rawValue: invitation.port)!, using: parameters)
        }
    }
    func connect() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let ready = LocalSyncReady(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: ready.finish(.success(()))
                    case .failed(let error): ready.finish(.failure(error))
                    case .cancelled: ready.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 15) { [connection] in
                    if case .ready = connection.state { return }
                    ready.finish(.failure(LocalSyncError.disconnected)); connection.cancel()
                }
            }
        } onCancel: { self.connection.cancel() }
    }
    func close() { connection.cancel() }
    func send(_ bytes: Data) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
    func receive(count: Int) async throws -> Data {
        guard count >= 0, count <= LocalSyncArchive.maximumFrameBytes else { throw LocalSyncError.invalidData }
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            let remaining = min(65_536, count - result.count)
            let bytes: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: complete ? LocalSyncError.disconnected : LocalSyncError.invalidData) }
                }
            }
            result.append(bytes)
        }
        return result
    }
    func sendJSON(_ bytes: Data) async throws {
        guard (2...LocalSyncArchive.maximumFrameBytes).contains(bytes.count) else { throw LocalSyncError.invalidData }
        let length = UInt32(bytes.count)
        try await send(Data([UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]) + bytes)
    }
    func receiveJSON() async throws -> Data {
        let header = try await receive(count: 4)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length >= 2, length <= UInt32(LocalSyncArchive.maximumFrameBytes) else { throw LocalSyncError.invalidData }
        return try await receive(count: Int(length))
    }
}
#endif
