import Foundation
import SwiftUI

enum ModelDisplay {
    static func name(_ manifest: ModelManifest) -> String {
        let families = ModelCatalog.families(for: manifest.purpose, speechPacks: BundledParakeetPacks.manifests)
        for family in families {
            if let variant = family.variants.first(where: {
                $0.id == manifest.modelID || ($0.manifest.upstreamRepository == manifest.upstreamRepository
                    && $0.manifest.artifacts.map(\.sha256) == manifest.artifacts.map(\.sha256))
            }) {
                return family.variants.count == 1 ? family.title : "\(family.title) \(variant.title)"
            }
        }
        if let pack = try? ParakeetModelPack.configuration(for: manifest) {
            return pack.decoderContract == "parakeet-tdt-v3" ? "Parakeet v3" : "Parakeet v2"
        }
        return manifest.upstreamRepository.lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }
    static func engine(_ manifest: ModelManifest) -> String {
        manifest.purpose == .speechRecognition ? "Core ML" : "GGUF"
    }
}

enum ModelScreen: Hashable, Identifiable {
    case variant(String), transfer, apple
    var id: Self { self }
}

/// Settings and contextual setup share the same finite, pinned catalogue.
struct ModelBrowserView: View {
    let controller: ModelBrowserController
    var application: RecordingApplication? = nil
    var body: some View {
        NavigationStack {
            ModelPurposeView(controller: controller, purpose: controller.purpose, application: application)
        }.tint(MinutesStyle.accent)
    }
}

struct ModelSetupSheet: View {
    let controller: ModelBrowserController
    let application: RecordingApplication?
    let purpose: ModelPurpose
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ModelPurposeView(controller: controller, purpose: purpose, application: application,
                             onSelected: { dismiss() })
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(MinutesStyle.accent)
    }
}

@MainActor
struct ModelPurposeView: View {
    @Bindable var controller: ModelBrowserController
    let purpose: ModelPurpose
    var application: RecordingApplication? = nil
    var onSelected: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var captureRoute: ModelScreen?
    @State private var pendingRemoval: ModelManifest?
    @State private var confirmingRemoval = false
    @State private var transferDetails = false
    @State private var screenshotPrepared = false
    @State private var appleAvailability: AppleSummaryAvailability

    init(controller: ModelBrowserController, purpose: ModelPurpose, application: RecordingApplication? = nil,
         onSelected: (() -> Void)? = nil) {
        self.controller = controller; self.purpose = purpose
        self.application = application; self.onSelected = onSelected
        _appleAvailability = State(initialValue: controller.appleAvailability)
        #if DEBUG
        if let scene = AppScreenshotFixture.scene {
            let variants = controller.families(for: purpose).flatMap(\.variants)
            switch scene {
            case .modelsDownloading, .modelsVerifying:
                _captureRoute = State(initialValue: .transfer)
            case .modelsDetails, .modelsRemove:
                _captureRoute = State(initialValue: variants.first.map { .variant($0.id) })
            case .modelsRepository, .modelsSource, .modelsCard, .modelsCompatibility,
                 .modelsRequirements, .modelsDownload, .modelsImport:
                _captureRoute = State(initialValue: variants.last.map { .variant($0.id) })
            default: break
            }
        } else if controller.downloadProgress != nil {
            _captureRoute = State(initialValue: .transfer)
        }
        #endif
    }

    private var busy: Bool { controller.isWorking || controller.isPreparingStorageCheck }
    private var title: String { purpose == .speechRecognition ? "Speech models" : "Summary & Q&A" }
    private var families: [ModelCatalogFamily] { controller.families(for: purpose) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(purpose == .speechRecognition
                        ? "Turn speech into text, on your iPhone."
                        : "Summarize meetings and ask questions, on your iPhone.")
                        .font(.headline)
                    Text("Download a model, then equip it to use it. Removing a download frees its storage.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let selected = controller.installed.first(where: {
                        $0.purpose == purpose && controller.isEquipped($0)
                    }) {
                        Label("Equipped: \(ModelDisplay.name(selected))", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(MinutesStyle.accent)
                            .accessibilityIdentifier("models.selection")
                    } else if purpose == .summary && controller.appleEquipped {
                        Label("Equipped: Apple Intelligence", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(MinutesStyle.accent)
                            .accessibilityIdentifier("models.selection")
                    } else {
                        Text("No model equipped").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("models.empty")
                    }
                    Text("\(bytes(controller.resources.freeDiskBytes)) free storage")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            feedbackSection
            if controller.isDownloading || controller.downloadProgress != nil {
                Section {
                    NavigationLink(value: ModelScreen.transfer) {
                        Label(controller.isDownloading ? "Download in progress" : "Latest download",
                              systemImage: "arrow.down.circle")
                    }.accessibilityIdentifier("models.transfer.open")
                }
            }
            if purpose == .summary { appleCatalogSection }
            ForEach(families, id: \.id) { family in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(family.title, systemImage: purpose == .speechRecognition ? "waveform" : "text.bubble")
                            .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            .accessibilityIdentifier("models.family.\(family.id)")
                        Text(family.detail).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    ForEach(family.variants, id: \.id) { variant in
                        variantRow(variant)
                    }
                }
            }
        }
        .minutesList().navigationTitle(title)
        .navigationDestination(for: ModelScreen.self, destination: page)
        .navigationDestination(item: $captureRoute, destination: page)
        .confirmationDialog("Remove this model?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove model", role: .destructive) {
                guard let manifest = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await controller.remove(manifest) }
            }.accessibilityIdentifier("models.remove.confirm")
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Downloaded model files and unfinished downloads will be deleted to free storage. Meetings and notes stay on this iPhone.")
        }
        .task {
            controller.purpose = purpose
            await controller.refresh()
            screenshotPrepared = true
        }
        .refreshable { await controller.refresh() }
        .screenshotReady(screenshotPrepared)
    }

    private var appleCatalogSection: some View {
        Section {
            NavigationLink(value: ModelScreen.apple) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Intelligence", systemImage: "sparkles")
                        .font(.title3.weight(.semibold)).accessibilityIdentifier("models.apple.title")
                    Text(controller.appleEquipped ? "Equipped · Built into iOS" : "Built into iOS")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(controller.appleAvailability.explanation).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("models.apple.availability")
                }.padding(.vertical, 8)
            }.accessibilityIdentifier("models.apple.open")
        }
    }

    private func variantRow(_ variant: ModelCatalogVariant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(variant.title).font(.headline)
                    .accessibilityIdentifier("models.title.\(variant.id)")
                Spacer(minLength: 0)
                if let installed = controller.installedManifest(for: variant.manifest) {
                    Label(controller.isEquipped(installed) ? "Equipped" : "Downloaded",
                          systemImage: controller.isEquipped(installed) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption.weight(.medium)).foregroundStyle(MinutesStyle.accent)
                        .accessibilityIdentifier("models.status.\(variant.id)")
                }
            }
            Text(variant.detail).font(.subheadline).foregroundStyle(.secondary)
            Text(repositoryName(variant.manifest)).font(.footnote).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("models.repository.\(variant.id)")
            Text("\(bytes(ModelBrowserController.downloadBytes(variant.manifest))) · \(ModelDisplay.engine(variant.manifest))")
                .font(.footnote).foregroundStyle(.secondary)
            if controller.transferManifest?.modelID == variant.id, controller.isDownloading {
                ProgressView(value: controller.downloadProgress?.overallFractionCompleted)
                    .accessibilityLabel("Downloading \(variant.title)")
            }
            actionLayout {
                modelActions(variant)
                NavigationLink("Details", value: ModelScreen.variant(variant.id))
                    .buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Details for \(modelActionIdentity(variant.manifest))")
                    .accessibilityIdentifier("models.open.\(variant.id)")
            }
        }.padding(.vertical, 10)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }

    @ViewBuilder private func modelActions(_ variant: ModelCatalogVariant) -> some View {
        if let installed = controller.installedManifest(for: variant.manifest) {
            Button(controller.isEquipped(installed) ? "Equipped" : "Equip") {
                Task {
                    await controller.equip(variant.manifest)
                    if let current = controller.installedManifest(for: variant.manifest), controller.isEquipped(current) {
                        onSelected?()
                    }
                }
            }
            .buttonStyle(.borderedProminent).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("\(controller.isEquipped(installed) ? "Equipped" : "Equip") \(modelActionIdentity(variant.manifest))")
            .accessibilityIdentifier("models.equip.\(variant.id)")
            .disabled(busy || controller.isEquipped(installed))
            removeButton(variant)
        } else if controller.transferManifest?.modelID == variant.id && controller.isDownloading {
            Button("Pause", systemImage: "pause") { controller.cancelDownload() }
                .buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Pause downloading \(modelActionIdentity(variant.manifest))")
                .accessibilityIdentifier("models.pause.\(variant.id)")
        } else {
            Button(controller.hasPartialDownload(variant.manifest) ? "Resume" : "Download", systemImage: "arrow.down") {
                controller.download(variant)
            }
            .buttonStyle(.borderedProminent).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("\(controller.hasPartialDownload(variant.manifest) ? "Resume downloading" : "Download") \(modelActionIdentity(variant.manifest))")
            .accessibilityIdentifier("models.download.\(variant.id)")
            .disabled(!controller.canDownload(variant))
            if controller.hasPartialDownload(variant.manifest) { removeButton(variant) }
        }
    }

    private func removeButton(_ variant: ModelCatalogVariant) -> some View {
        Button("Remove", role: .destructive) {
            pendingRemoval = variant.manifest; confirmingRemoval = true
        }
        .buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Remove \(modelActionIdentity(variant.manifest))")
        .accessibilityIdentifier("models.remove.\(variant.id)").disabled(busy)
    }

    @ViewBuilder private func page(_ route: ModelScreen) -> some View {
        Group {
            switch route {
            case .variant(let id):
                if let variant = controller.variant(id: id) { detailsPage(variant) }
                else { ContentUnavailableView("Model unavailable", systemImage: "exclamationmark.circle") }
            case .transfer: transferPage
            case .apple: applePage
            }
        }.navigationBarTitleDisplayMode(.inline).tint(MinutesStyle.accent).screenshotReady(true)
    }

    private func detailsPage(_ variant: ModelCatalogVariant) -> some View {
        Form {
            Section {
                Text(variant.title).font(.title2.weight(.semibold))
                    .accessibilityIdentifier("models.details.title")
                Text(variant.detail).foregroundStyle(.secondary)
                Text(repositoryName(variant.manifest)).font(.subheadline).textSelection(.enabled)
                    .accessibilityIdentifier("models.repository.title")
                actionLayout { modelActions(variant) }
            }
            feedbackSection
            Section("Download & storage") {
                LabeledContent("Download size", value: bytes(ModelBrowserController.downloadBytes(variant.manifest)))
                LabeledContent("Free storage", value: bytes(controller.resources.freeDiskBytes))
                Text("Installation temporarily needs up to twice the download size. Model memory requirements are additional and depend on your iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !busy, controller.installedManifest(for: variant.manifest) == nil, !controller.canDownload(variant) {
                    Text("Not enough free storage for this download. Remove another model and try again.")
                        .font(.callout).foregroundStyle(MinutesStyle.recording)
                }
            }
            Section("Source & license") {
                LabeledContent("Format", value: ModelDisplay.engine(variant.manifest))
                LabeledContent("License", value: variant.manifest.licenseIdentifier)
                Text(variant.manifest.runtimeVersion).font(.footnote).textSelection(.enabled)
                    .accessibilityIdentifier("models.runtime.\(variant.id)")
                DisclosureGroup("Source revision & files") {
                    Text(variant.manifest.revision).font(.caption.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("models.repository.revision")
                    ForEach(variant.manifest.artifacts, id: \.fileName) { artifact in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(artifact.fileName).font(.footnote).textSelection(.enabled)
                            Text(bytes(artifact.byteCount)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DisclosureGroup("Attribution & terms") {
                    Text(variant.manifest.licenseNotice).font(.footnote).textSelection(.enabled)
                        .accessibilityIdentifier("models.license.notice")
                }.accessibilityIdentifier("models.license.open")
                Link("View publisher repository", destination: variant.manifest.upstreamRepository)
                    .frame(minHeight: 44)
            }
        }.minutesList().navigationTitle("Model details")
    }

    private var transferPage: some View {
        List {
            if let manifest = controller.transferManifest {
                Section {
                    Text(ModelDisplay.name(manifest)).font(.headline)
                    Text(repositoryName(manifest)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let progress = controller.downloadProgress {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(stageTitle(progress.stage)).font(.title2.weight(.semibold))
                            .accessibilityIdentifier("models.download.stage")
                        Text((progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                            .formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit().accessibilityIdentifier("models.download.percent")
                        ProgressView(value: progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                            .accessibilityIdentifier("models.download.progress")
                        Text("\(bytes(progress.overallCompletedBytes)) of \(bytes(progress.overallTotalBytes))")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("models.download.bytes")
                        if controller.isDownloading {
                            Button("Pause download") { controller.cancelDownload() }.frame(minHeight: 44)
                                .accessibilityIdentifier("models.download.pause")
                        } else if progress.stage == .paused || progress.stage == .failed {
                            Button("Resume download") { controller.resumeDownload() }.frame(minHeight: 44)
                                .disabled(busy).accessibilityIdentifier("models.download.resume")
                        }
                    }.padding(.vertical, 12)
                }
                Section {
                    DisclosureGroup("Transfer details", isExpanded: $transferDetails) {
                        Text("File \(progress.fileIndex) of \(progress.fileCount)").accessibilityIdentifier("models.download.file")
                        Text(progress.fileName).font(.footnote).textSelection(.enabled)
                            .accessibilityIdentifier("models.download.filename")
                        if progress.stage == .downloading {
                            Text(transferSpeed(progress.bytesPerSecond)).accessibilityIdentifier("models.download.speed")
                            Text(timeRemaining(progress.remainingSeconds)).accessibilityIdentifier("models.download.remaining")
                        }
                        if progress.resumedBytes > 0 {
                            Text("Resumed \(bytes(progress.resumedBytes))").accessibilityIdentifier("models.download.resumed")
                        }
                    }.accessibilityIdentifier("models.download.details")
                }
            } else if controller.isDownloading {
                Section { ProgressView("Preparing download…") }
            } else {
                Section { Text("No download in progress.").foregroundStyle(.secondary) }
            }
            if !controller.isWorking, let manifest = controller.transferManifest,
               let variant = controller.variant(id: manifest.modelID) {
                Section { actionLayout { modelActions(variant) } }
            }
            feedbackSection
        }.minutesList().navigationTitle("Model transfer")
    }

    private var applePage: some View {
        Form {
            Section {
                Label("Apple Intelligence", systemImage: "sparkles").font(.title2.weight(.semibold))
                    .accessibilityIdentifier("models.apple.title")
                Text("Built into iOS. Model downloads and storage are managed in iPhone Settings.")
                    .foregroundStyle(.secondary)
                Text(appleAvailability.explanation).accessibilityIdentifier("models.apple.availability")
                Button(controller.appleEquipped ? "Equipped" : "Equip Apple Intelligence") {
                    Task {
                        await controller.equipAppleIntelligence()
                        if controller.appleEquipped { onSelected?() }
                    }
                }
                .frame(minHeight: 44).accessibilityIdentifier("models.apple.equip")
                .disabled(busy || controller.appleEquipped || appleAvailability != .available)
                if appleAvailability != .available {
                    Button("Check again") { appleAvailability = controller.appleAvailability }
                        .frame(minHeight: 44).accessibilityIdentifier("models.apple.refresh")
                }
            }
            feedbackSection
        }.minutesList().navigationTitle("Apple Intelligence")
            .onAppear { appleAvailability = controller.appleAvailability }
    }

    @ViewBuilder private var feedbackSection: some View {
        if let error = controller.errorMessage {
            Section { Text(error).foregroundStyle(MinutesStyle.recording).accessibilityIdentifier("models.error") }
        } else if let message = controller.message {
            Section { Text(message).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("models.message") }
        }
    }

    private func repositoryName(_ manifest: ModelManifest) -> String {
        manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private func modelActionIdentity(_ manifest: ModelManifest) -> String {
        "\(manifest.purpose == .speechRecognition ? "speech" : "summary") model \(repositoryName(manifest))"
    }
    private func stageTitle(_ stage: ModelTransferStage) -> String {
        switch stage {
        case .preparing: "Preparing download"
        case .downloading: "Downloading"
        case .verifying: "Verifying files"
        case .installing: "Installing"
        case .completed: "Ready to equip"
        case .paused: "Download paused"
        case .failed: "Download interrupted"
        }
    }
    private func timeRemaining(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "Estimating time remaining…" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated; formatter.maximumUnitCount = 2
        return "About \(formatter.string(from: max(1, min(seconds, 86_400 * 365))) ?? "1s") remaining"
    }
    private func transferSpeed(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "Measuring speed…" }
        return "\(bytes(Int64(min(value, Double(Int64.max / 2)))))/s"
    }
    private func bytes(_ value: Int64?) -> String {
        guard let value, value >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
