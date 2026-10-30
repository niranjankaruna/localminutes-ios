#if os(iOS)
import Foundation
import Observation
import Security

@MainActor @Observable
final class LocalSyncController {
    let application: RecordingApplication
    let replicaID: UUID
    private static let processRunID = UUID()
    let runID = LocalSyncController.processRunID
    private(set) var invitation: LocalSyncInvitation?
    private(set) var status = "Pair with Windows, then keep this screen open on the same Wi-Fi."
    private(set) var connected = false
    private(set) var transferring = false
    private(set) var progress: Double = 0
    var code = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var connection: LocalSyncConnection?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var wantsSend = false
    @ObservationIgnored private let discovery = LocalSyncDiscovery()
    private let keychainService = "com.niranjankaruna.localminutes.localsync.v1"

    init(application: RecordingApplication) {
        self.application = application
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "localSync.replicaID"), let value = UUID(uuidString: stored) { replicaID = value }
        else { let value = UUID(); replicaID = value; defaults.set(value.uuidString, forKey: "localSync.replicaID") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
                                   kSecAttrAccount as String: "windows", kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            do { invitation = try JSONDecoder().decode(LocalSyncInvitation.self, from: data).validated() }
            catch { status = "Saved pairing is invalid. Pair with your PC again." }
        }
    }
    func pair(_ scanned: String? = nil) {
        do {
            let text = (scanned ?? code).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "localminutes://pair/"
            guard text.hasPrefix(prefix), let data = Data(base64Encoded: String(text.dropFirst(prefix.count))), data.count <= 4_096 else { throw LocalSyncError.invalidData }
            let value = try JSONDecoder().decode(LocalSyncInvitation.self, from: data).validated()
            guard value.replicaId != replicaID.uuidString else { throw LocalSyncError.identityCollision }
            stop()
            if invitation?.replicaId != value.replicaId { UserDefaults.standard.removeObject(forKey: "localSync.pendingOutgoing") }
            invitation = value; code = ""; wantsSend = false; start()
        } catch { status = "That pairing invitation is invalid. Generate a new one on Windows." }
    }
    func forget() {
        stop(); invitation = nil
        wantsSend = false; UserDefaults.standard.removeObject(forKey: "localSync.pendingOutgoing")
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "windows"] as CFDictionary)
        status = "Pairing removed. Your meetings have not been deleted."
    }
    private func savePairing(_ value: LocalSyncInvitation) throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "windows"]
        let data = try JSONEncoder().encode(value)
        var result = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var creation = key; creation[kSecValueData as String] = data; creation[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            result = SecItemAdd(creation as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw LocalSyncError.unpaired }
    }
    func sendLibrary() {
        guard invitation != nil else { status = "Pair with your Windows PC first."; return }
        wantsSend = true; start()
    }
    func start() {
        guard task == nil, let invitation else { return }
        let session = UUID(); generation = session
        task = Task { @MainActor in
            defer {
                if generation == session { connection?.close(); discovery.stop(); connection = nil; connected = false; transferring = false; task = nil }
            }
            do {
                status = "Finding your paired Windows PC…"
                discovery.start(targetID: invitation.replicaId)
                for _ in 0..<20 {
                    if discovery.discovered != nil { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                let channel = try LocalSyncConnection(invitation: invitation, service: discovery.discovered); connection = channel
                status = "Connecting to \(invitation.name)…"; try await channel.connect()
                let response = try await exchange(["command": "hello", "version": 1, "replicaId": replicaID.uuidString, "runId": runID.uuidString, "name": "My iPhone", "token": invitation.token], channel: channel)
                guard response["status"] as? String == "ready", response["replicaId"] as? String == invitation.replicaId else { throw LocalSyncError.unpaired }
                try savePairing(invitation); connected = true; status = "Connected. Tap Sync here to send, or Sync on Windows to receive."
                while !Task.isCancelled {
                    if wantsSend { wantsSend = false; try await push(channel) }
                    let reply = try await exchange(["command": "poll"], channel: channel)
                    if reply["status"] as? String == "offer", let payload = reply["manifest"] as? [String: Any] {
                        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
                        let manifest = try JSONDecoder().decode(LocalSyncManifest.self, from: data)
                        guard manifest.sourceId == invitation.replicaId else { throw LocalSyncError.unpaired }
                        try await pull(manifest, data: data, channel: channel)
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError { if generation == session { status = "Sync paused. Keep this screen open to reconnect." } }
            catch {
                if generation == session {
                    if (error as? LibraryArchiveCoordinatorError) == .busy {
                        status = "Finish recording, playback or generation, then reconnect to sync."
                    } else if let problem = error as? LocalSyncError {
                        switch problem {
                        case .insufficientSpace: status = "There is not enough free storage to receive this library. Free space and reconnect."
                        case .busy: status = "Finish recording, playback or generation, then reconnect to sync."
                        case .unpaired: status = "Device trust could not be verified. Pair with your Windows PC again."
                        case .unsupportedVersion: status = "Update LocalMinutes on both devices before syncing."
                        case .integrityMismatch, .identityCollision, .invalidData: status = "The transfer failed validation. Existing meeting data was retained. Reconnect to retry."
                        case .disconnected: status = "Connection interrupted. Keep both apps open on the same Wi-Fi and reconnect."
                        }
                    } else { status = "Sync stopped safely. Check Wi-Fi, Local Network permission in iPhone Settings, Windows Firewall, and that both apps are open." }
                }
            }
        }
    }
    func stop() {
        task?.cancel(); connection?.close(); discovery.stop(); task = nil; connection = nil; generation = UUID(); connected = false; transferring = false
    }
    private func exchange(_ object: [String: Any], channel: LocalSyncConnection) async throws -> [String: Any] {
        try await channel.sendJSON(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
        let data = try await channel.receiveJSON()
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LocalSyncError.invalidData }
        return result
    }
    private func root(_ name: String) throws -> URL {
        guard let services = application.services else { throw LocalSyncError.busy }
        let url = services.applicationRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); try PersistentFilePolicy.protectDirectory(url)
        return url
    }
    private func push(_ channel: LocalSyncConnection) async throws {
        transferring = true; progress = 0; defer { transferring = false }
        status = "Preparing all saved meeting data…"
        let source: URL
        let parent = try root("SyncOutgoing")
        if let pending = UserDefaults.standard.string(forKey: "localSync.pendingOutgoing"), let id = UUID(uuidString: pending),
           FileManager.default.fileExists(atPath: parent.appendingPathComponent(id.uuidString).path) {
            source = parent.appendingPathComponent(id.uuidString, isDirectory: true)
        } else {
            source = try await application.exportLocalSync(sourceID: replicaID)
            UserDefaults.standard.set(source.lastPathComponent, forKey: "localSync.pendingOutgoing")
        }
        let manifest = try await Self.worker { try LocalSyncArchive.validate(source) }
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("manifest.json")))
        let offered = try await exchange(["command": "push", "manifest": payload], channel: channel)
        guard offered["status"] as? String == "accept" else { throw LocalSyncError.busy }
        let total = manifest.files.reduce(Int64(0)) { $0 + $1.byteCount }; var completed: Int64 = 0
        for file in manifest.files {
            let reply = try await exchange(["command": "offset", "path": file.relativePath], channel: channel)
            guard let offset = reply["offset"] as? Int64, offset >= 0, offset <= file.byteCount else { throw LocalSyncError.invalidData }
            let input = try FileHandle(forReadingFrom: LocalSyncArchive.file(file.relativePath, within: source))
            do {
                try input.seek(toOffset: UInt64(offset)); var sent = offset
                while sent < file.byteCount {
                    try Task.checkCancellation()
                    guard let bytes = try input.read(upToCount: Int(min(65_536, file.byteCount - sent))), !bytes.isEmpty else { throw LocalSyncError.invalidData }
                    try await channel.sendJSON(JSONSerialization.data(withJSONObject: ["command": "put", "path": file.relativePath, "offset": sent, "bytes": bytes.count]))
                    try await channel.send(bytes)
                    let response = try await channel.receiveJSON()
                    guard let ack = try JSONSerialization.jsonObject(with: response) as? [String: Any], ack["status"] as? String == "saved", ack["offset"] as? Int64 == sent + Int64(bytes.count) else { throw LocalSyncError.invalidData }
                    sent += Int64(bytes.count); progress = total == 0 ? 0 : Double(completed + sent) / Double(total)
                    status = "Sending iPhone library to Windows…"
                }
                try input.close(); completed += file.byteCount
            } catch { try? input.close(); throw error }
        }
        let receipt = try await exchange(["command": "commit"], channel: channel)
        guard receipt["status"] as? String == "complete" else { throw LocalSyncError.busy }
        UserDefaults.standard.removeObject(forKey: "localSync.pendingOutgoing"); progress = 1
        status = "Windows confirmed your meeting data was saved. Models stayed on this iPhone."
    }
    private func pull(_ manifest: LocalSyncManifest, data: Data, channel: LocalSyncConnection) async throws {
        try LocalSyncArchive.validateManifest(manifest)
        transferring = true; progress = 0; defer { transferring = false }
        let parent = try root("SyncIncoming"), destination = parent.appendingPathComponent(manifest.transferId, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true); try PersistentFilePolicy.protectDirectory(destination)
        let manifestURL = destination.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            guard try JSONDecoder().decode(LocalSyncManifest.self, from: Data(contentsOf: manifestURL)) == manifest else { throw LocalSyncError.identityCollision }
        } else { try PersistentFilePolicy.writeAtomically(data, to: manifestURL, within: destination) }
        let total = manifest.files.reduce(Int64(0)) { $0 + $1.byteCount }
        let capacity = try destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity > total, capacity - total > 100_000_000 else { throw LocalSyncError.insufficientSpace }
        var completed: Int64 = 0
        for file in manifest.files {
            let target = try LocalSyncArchive.file(file.relativePath, within: destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path), try LocalSyncArchive.digest(target) == file.sha256 { completed += file.byteCount; continue }
            if !FileManager.default.fileExists(atPath: target.path), let library = application.services?.libraryRoot {
                let local = try LocalSyncArchive.file(file.relativePath, within: library)
                if FileManager.default.fileExists(atPath: local.path), try LocalSyncArchive.digest(local) == file.sha256 {
                    try FileManager.default.copyItem(at: local, to: target)
                    try PersistentFilePolicy.protectItem(target, within: destination)
                    completed += file.byteCount; continue
                }
            }
            let partial = target.appendingPathExtension("part")
            var offset = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if offset > file.byteCount { try FileManager.default.removeItem(at: partial); offset = 0 }
            if !FileManager.default.fileExists(atPath: partial.path) { guard FileManager.default.createFile(atPath: partial.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else { throw LocalSyncError.invalidData } }
            try PersistentFilePolicy.protectItem(partial, within: destination)
            let output = try FileHandle(forWritingTo: partial)
            do {
                try output.seekToEnd()
                while offset < file.byteCount {
                    let response = try await exchange(["command": "get", "path": file.relativePath, "offset": offset], channel: channel)
                    guard response["status"] as? String == "chunk", let count = response["bytes"] as? Int, (1...65_536).contains(count), Int64(count) <= file.byteCount - offset else { throw LocalSyncError.invalidData }
                    let bytes = try await channel.receive(count: count); try output.write(contentsOf: bytes); try output.synchronize(); offset += Int64(count)
                    progress = total == 0 ? 0 : Double(completed + offset) / Double(total); status = "Receiving Windows meeting data…"
                }
                try output.close()
            } catch { try? output.close(); throw error }
            guard try LocalSyncArchive.digest(partial) == file.sha256 else { try? FileManager.default.removeItem(at: partial); throw LocalSyncError.integrityMismatch }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: partial, to: target); completed += file.byteCount
        }
        status = "Verifying and saving your library…"
        try await application.restoreLibrary(from: destination, mergingLocalSync: true)
        let receipt = try await exchange(["command": "received", "transferId": manifest.transferId], channel: channel)
        guard receipt["status"] as? String == "complete" else { throw LocalSyncError.invalidData }
        progress = 1; status = "Windows library saved. Meetings only on this iPhone were kept."
    }

    nonisolated private static func worker<Value: Sendable>(
        _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .utility) { try body() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
#endif
