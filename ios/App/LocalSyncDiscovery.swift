#if os(iOS)
import Foundation

struct LocalSyncDiscoveredService: Sendable {
    let name: String
}

/// Discovery records are untrusted routing hints. LocalSyncConnection still pins the paired TLS identity.
@MainActor final class LocalSyncDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]
    private var targetID: String?
    private(set) var discovered: LocalSyncDiscoveredService?

    func start(targetID: String) {
        stop(); self.targetID = targetID
        let next = NetServiceBrowser(); next.delegate = self; browser = next
        next.searchForServices(ofType: "_localminutes._tcp.", inDomain: "local.")
    }
    func stop() {
        browser?.stop(); browser?.delegate = nil; browser = nil
        for service in services.values { service.stop(); service.delegate = nil }
        services.removeAll(); discovered = nil; targetID = nil
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.type.lowercased() == "_localminutes._tcp.", service.domain.lowercased() == "local.", service.name.utf8.count <= 63 else { return }
        guard let targetID, service.name.caseInsensitiveCompare("LocalMinutes-" + targetID) == .orderedSame else { return }
        services[service.name] = service; service.delegate = self; service.resolve(withTimeout: 2)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)?.stop()
        if discovered?.name == service.name { discovered = nil }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let record = sender.txtRecordData() else { return }
        let fields = NetService.dictionary(fromTXTRecord: record)
        guard let id = fields["id"], String(data: id, encoding: .utf8) == targetID,
              let version = fields["v"], String(data: version, encoding: .utf8) == "1" else { return }
        discovered = LocalSyncDiscoveredService(name: sender.name)
    }
}
#endif
