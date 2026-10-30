#if os(iOS)
import SwiftUI
import VisionKit
import Vision

@MainActor struct LocalSyncView: View {
    @State private var controller: LocalSyncController
    @State private var showingScanner = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(application: RecordingApplication) { _controller = State(initialValue: LocalSyncController(application: application)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("This iPhone") {
                    LabeledContent("Device ID", value: String(controller.replicaID.uuidString.prefix(8)))
                    Text("No account is needed. Your device identity stays the same after reopening the app.").font(.footnote).foregroundStyle(.secondary)
                }
                if let peer = controller.invitation {
                    Section("My iPhone → \(peer.name)") {
                        Text(controller.status).accessibilityIdentifier("sync.status")
                        if controller.transferring { ProgressView(value: controller.progress) }
                        Button("Sync iPhone library to Windows") { controller.sendLibrary() }
                            .disabled(controller.transferring).accessibilityIdentifier("sync.send")
                        Button(controller.connected ? "Disconnect" : "Connect") {
                            if controller.connected { controller.stop() } else { controller.start() }
                        }.disabled(controller.transferring)
                        Button("Forget Windows PC", role: .destructive) { controller.forget() }.disabled(controller.transferring)
                    }
                    Section {
                        Text("Your iPhone's edits replace matching edits on Windows. Meetings only on Windows are kept. Deletions and downloaded models are not copied.")
                        Text("To receive data, press Sync in Windows. Keep this Sync screen open and your iPhone unlocked until the transfer finishes.")
                    }
                }
                Section("Pair with Windows") {
                    Text("On Windows, open Sync and choose Pair an iPhone. Scan its invitation or paste the connection code below.")
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        Button("Scan Windows invitation") { showingScanner = true }.disabled(controller.transferring)
                    }
                    TextField("Connection code", text: $controller.code, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button("Pair using code") { controller.pair() }.disabled(controller.code.isEmpty || controller.transferring)
                    if controller.invitation == nil { Text(controller.status).font(.footnote) }
                }
                Section {
                    Text("Both devices need a reachable local network. No internet server is used. Windows Firewall and isolated guest Wi-Fi can block the connection.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sync")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controller.stop(); dismiss() } } }
            .sheet(isPresented: $showingScanner) { LocalSyncScanner { code in controller.pair(code); showingScanner = false } }
            .task { controller.start() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { controller.start() } else { controller.stop() } }
            .onDisappear { if !showingScanner { controller.stop() } }
        }
    }
}

@MainActor private struct LocalSyncScanner: UIViewControllerRepresentable {
    let found: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { context.coordinator.unavailable(scanner) }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) { }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var consumed = false
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !consumed else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, code.hasPrefix("localminutes://pair/") {
                    consumed = true; scanner.stopScanning(); found(code); return
                }
            }
        }
        func unavailable(_ scanner: DataScannerViewController) {
            let label = UILabel(); label.text = "Camera scanning is unavailable. Close this sheet and paste the connection code instead."; label.numberOfLines = 0
            label.textAlignment = .center; label.frame = scanner.view.bounds.insetBy(dx: 24, dy: 80); label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; scanner.view.addSubview(label)
        }
    }
}
#endif
