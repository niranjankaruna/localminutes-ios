#if DEBUG && os(iOS)
import CryptoKit
import Foundation
import SwiftUI

/// UI-only boundary fixture: real installer/controller/view, synthetic bytes.
/// These files are not inference models and are never equipped or evaluated.
@MainActor
enum ModelBrowserAccessibilityFixture {
    static let releaseCanary = "LOCALMINUTES_DEBUG_MODEL_ACCESSIBILITY_FIXTURE_CANARY_v1"
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-model-accessibility")
    }

    static func makeServices() async throws -> LocalMinutesServices {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("LocalMinutesModelAccessibilityUI", isDirectory: true)
        // Each launch owns a new root; no default app storage or private data is read.
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root)
        let revision = String(repeating: "a", count: 40)
        var variants: [ModelCatalogVariant] = []
        for name in ["alpha", "beta"] {
            let bytes = Data("Synthetic \(name) model-list UI fixture; not inference weights.".utf8)
            let input = root.appendingPathComponent("Input-\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
            try bytes.write(to: input.appendingPathComponent("fixture.gguf"))
            let repository = URL(string: "https://huggingface.co/example/ui-model-\(name)")!
            let manifest = ModelManifest(modelID: "ui-model-\(name)", purpose: .summary,
                upstreamRepository: repository, revision: revision,
                licenseIdentifier: "MIT", licenseNotice: "Synthetic UI fixture only.",
                runtimeVersion: "llama.cpp-b5046", artifacts: [
                    .init(role: .summary, fileName: "fixture.gguf", byteCount: Int64(bytes.count),
                        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                        downloadURL: repository.appendingPathComponent("resolve/\(revision)/fixture.gguf"),
                        digestProvenance: .upstreamReported)
                ])
            _ = try await services.models.importDirectory(input, manifest: manifest)
            variants.append(.init(id: manifest.modelID, title: name == "alpha" ? "0.5B" : "1.5B",
                detail: "Synthetic UI fixture · not inference weights", manifest: manifest, profile: .llamaGGUF))
        }
        let productionFamilies = ModelCatalog.families(for: .summary)
        let summaryFamilies = productionFamilies.enumerated().map { index, family in
            index == 0 ? ModelCatalogFamily(id: family.id, title: family.title, detail: family.detail,
                purpose: .summary, variants: variants) : family
        }
        services.modelBrowser.useFixtureCatalog(
            ModelCatalog.families(for: .speechRecognition, speechPacks: BundledParakeetPacks.manifests) + summaryFamilies)
        services.modelBrowser.purpose = .summary
        if ProcessInfo.processInfo.environment["LOCALMINUTES_UI_MODEL_PURPOSE"] == "speech" {
            services.modelBrowser.purpose = .speechRecognition
        }
        await services.modelBrowser.refresh()
        AppScreenshotFixture.prepareModels(services.modelBrowser)
        let screenshotStage: String? = AppScreenshotFixture.scene == .modelsDownloading ? "downloading" :
            AppScreenshotFixture.scene == .modelsVerifying ? "verifying" : nil
        if let stage = screenshotStage ?? ProcessInfo.processInfo.environment["LOCALMINUTES_UI_MODEL_PROGRESS"], stage != "idle" {
            services.modelBrowser.updateDownloadProgress(.init(
                stage: stage == "verifying" ? .verifying : .downloading,
                fileName: "Encoder.mlmodelc/weights/weight.bin", completedBytes: 104_857_600,
                totalBytes: 209_715_200, bytesPerSecond: stage == "verifying" ? nil : 10_485_760,
                remainingSeconds: stage == "verifying" ? nil : 10,
                resumedBytes: 52_428_800, fileIndex: 2, fileCount: 5,
                overallCompletedBytes: 209_715_200, overallTotalBytes: 419_430_400))
        }
        return services
    }
}

@MainActor
struct ModelBrowserAccessibilityFixtureRoot: View {
    @State private var services: LocalMinutesServices?
    @State private var finished = false
    private var largestText: Bool {
        ProcessInfo.processInfo.environment["LOCALMINUTES_UI_MODEL_AX5"] == "1"
    }

    var body: some View {
        Group {
            if let services {
                if largestText {
                    ModelBrowserView(controller: services.modelBrowser).dynamicTypeSize(.accessibility5)
                } else {
                    ModelBrowserView(controller: services.modelBrowser)
                }
            } else if finished {
                Text("Model accessibility fixture unavailable.")
                    .accessibilityIdentifier("ui.fixture.models.failure")
            } else {
                ProgressView("Preparing model accessibility fixture…")
            }
        }
        .accessibilityIdentifier(ModelBrowserAccessibilityFixture.releaseCanary)
        .preferredColorScheme(AppScreenshotFixture.colorScheme)
        .task {
            guard !finished else { return }
            defer { finished = true }
            services = try? await ModelBrowserAccessibilityFixture.makeServices()
        }
    }
}
#endif
