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
    case variant(String), transfer
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
        }.minutesSheet()
    }
}

@MainActor
struct ModelPurposeView: View {
    @Bindable var controller: ModelBrowserController
    let purpose: ModelPurpose
    var application: RecordingApplication? = nil
    var onSelected: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedFamilies: Set<String> = []
    @State private var captureRoute: ModelScreen?
    @State private var pendingRemoval: ModelManifest?
    @State private var confirmingRemoval = false
    @State private var transferDetails = false
    @State private var screenshotPrepared = false
    @State private var screenshotDetailsPrepared = false
    @State private var attributionExpanded = false

    init(controller: ModelBrowserController, purpose: ModelPurpose, application: RecordingApplication? = nil,
         onSelected: (() -> Void)? = nil) {
        self.controller = controller; self.purpose = purpose
        self.application = application; self.onSelected = onSelected
        #if DEBUG
        if let scene = AppScreenshotFixture.scene {
            switch scene {
            case .modelsDownloading, .modelsVerifying:
                _captureRoute = State(initialValue: .transfer)
            case .modelsInstalled, .modelsRemove:
                if let family = controller.families(for: purpose).first(where: {
                    $0.variants.contains(where: { $0.id == "ui-model-alpha" })
                }) {
                    _expandedFamilies = State(initialValue: [family.id])
                }
            case .modelsDetails:
                _captureRoute = State(initialValue: .variant("ui-model-alpha"))
            case .modelsRepository, .modelsSource, .modelsCard, .modelsDownload:
                let variant = controller.families(for: .speechRecognition)
                    .first(where: { $0.id == "parakeet-v2" })?.variants.first
                _captureRoute = State(initialValue: variant.map { .variant($0.id) })
                _attributionExpanded = State(initialValue: scene == .modelsCard)
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
        ScrollViewReader { proxy in
            modelList.screenshotScroll(proxy, ready: screenshotPrepared)
        }
    }

    private var modelList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(purpose == .speechRecognition
                        ? "Turn speech into text, on your iPhone."
                        : "Summarize meetings and ask questions, on your iPhone.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let selected = controller.installed.first(where: {
                        $0.purpose == purpose && controller.isEquipped($0)
                    }) {
                        Label("In use: \(ModelDisplay.name(selected))", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(MinutesStyle.accent)
                            .accessibilityIdentifier("models.selection")
                    } else {
                        Text("Choose a model below to get started.").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("models.empty")
                    }
                    Text("\(bytes(controller.resources.freeDiskBytes)) free storage")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            } footer: {
                Text("Download once, then choose Use model. Models run offline on this iPhone.")
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
            ForEach(families, id: \.id) { family in
                Section {
                    DisclosureGroup(isExpanded: familyExpansion(family.id)) {
                        Text(family.detail)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                        ForEach(family.variants, id: \.id) { variant in
                            variantRow(variant)
                                .screenshotAnchor(variant.id)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(family.title, systemImage: purpose == .speechRecognition ? "waveform" : "text.bubble")
                                .font(.headline).foregroundStyle(.primary)
                            Text(familySubtitle(family)).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: 44, alignment: .leading).padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("models.family.\(family.id)")
                    }
                }
            }
        }
        .minutesList().navigationTitle(title)
        .navigationDestination(for: ModelScreen.self, destination: page)
        .navigationDestination(item: $captureRoute, destination: page)
        .alert("Remove this model?", isPresented: $confirmingRemoval) {
            Button("Remove model", role: .destructive) {
                guard let manifest = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await controller.remove(manifest) }
            }.accessibilityIdentifier("models.remove.confirm")
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removalMessage)
        }
        .task {
            controller.purpose = purpose
            await controller.refresh()
            screenshotPrepared = true
        }
        .refreshable { await controller.refresh() }
        .screenshotReady(screenshotPrepared)
    }

    private var removalMessage: String {
        guard let model = pendingRemoval else { return "Downloaded files will be removed. Your meetings are kept." }
        let message = "Downloaded files for \(ModelDisplay.name(model)) will be removed. Your meetings are kept."
        guard controller.isEquipped(model) else { return message }
        return message + (model.purpose == .speechRecognition
            ? " Choose another speech model to record again."
            : " Choose another model for summaries and answers.")
    }

    private func familyExpansion(_ id: String) -> Binding<Bool> {
        Binding(get: { expandedFamilies.contains(id) }, set: { expanded in
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                if expanded { expandedFamilies.insert(id) }
                else { expandedFamilies.remove(id) }
            }
        })
    }

    private func familySubtitle(_ family: ModelCatalogFamily) -> String {
        let count = family.variants.count
        let variants = count == 1 ? "1 variant" : "\(count) variants"
        if let equipped = family.variants.first(where: { variant in
            controller.installedManifest(for: variant.manifest).map { controller.isEquipped($0) } ?? false
        }) {
            return "\(variants) · \(equipped.title) in use"
        }
        return variants
    }

    private func variantRow(_ variant: ModelCatalogVariant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(variant.title).font(.headline)
                    .accessibilityIdentifier("models.title.\(variant.id)")
                Text(bytes(ModelBrowserController.downloadBytes(variant.manifest)))
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("Download size: \(bytes(ModelBrowserController.downloadBytes(variant.manifest)))")
                if let installed = controller.installedManifest(for: variant.manifest) {
                    Label(controller.isEquipped(installed) ? "In use" : "Downloaded",
                          systemImage: controller.isEquipped(installed) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(MinutesStyle.accent)
                        .accessibilityIdentifier("models.status.\(variant.id)")
                }
            }
            variantContext(variant)
            if controller.transferManifest?.modelID == variant.id, controller.isDownloading {
                ProgressView(value: controller.downloadProgress?.overallFractionCompleted)
                    .accessibilityLabel("Downloading \(variant.title)")
            }
            MinutesActions {
                modelActions(variant)
                NavigationLink("Details", value: ModelScreen.variant(variant.id))
                    .buttonStyle(MinutesButtonStyle(kind: .secondary))
                    .accessibilityLabel("Details for \(modelActionIdentity(variant.manifest))")
                    .accessibilityIdentifier("models.open.\(variant.id)")
            }
        }.padding(.vertical, 12)
    }

    @ViewBuilder private func variantContext(_ variant: ModelCatalogVariant) -> some View {
        if let context = variant.contextWindow {
            let contextLabel = Text("Context: \(context.maximumTokens.formatted())")
                .accessibilityLabel("Context: \(context.maximumTokens.formatted()) tokens")
                .accessibilityIdentifier("models.context.\(variant.id)")
            let outputLabel = Text("Output: \(context.outputTokenLimit.formatted())")
                .accessibilityLabel("Summary output: up to \(context.outputTokenLimit.formatted()) tokens")
                .accessibilityIdentifier("models.output.\(variant.id)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    contextLabel
                    Text("·").accessibilityHidden(true)
                    outputLabel
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    contextLabel
                    outputLabel
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func modelActions(_ variant: ModelCatalogVariant) -> some View {
        if let installed = controller.installedManifest(for: variant.manifest) {
            Button(controller.isEquipped(installed) ? "In use" : "Use model") {
                Task {
                    await controller.equip(variant.manifest)
                    if let current = controller.installedManifest(for: variant.manifest), controller.isEquipped(current) {
                        onSelected?()
                    }
                }
            }
            .buttonStyle(MinutesButtonStyle())
            .accessibilityLabel("\(controller.isEquipped(installed) ? "Using" : "Use") \(modelActionIdentity(variant.manifest))")
            .accessibilityIdentifier("models.equip.\(variant.id)")
            .disabled(busy || controller.isEquipped(installed))
            removeButton(variant)
        } else if controller.transferManifest?.modelID == variant.id && controller.isDownloading {
            Button("Pause", systemImage: "pause") { controller.cancelDownload() }
                .buttonStyle(MinutesButtonStyle(kind: .secondary))
                .accessibilityLabel("Pause downloading \(modelActionIdentity(variant.manifest))")
                .accessibilityIdentifier("models.pause.\(variant.id)")
        } else {
            Button {
                controller.download(variant)
            } label: {
                Label(controller.hasPartialDownload(variant.manifest) ? "Resume" : "Download", systemImage: "arrow.down")
            }
            .buttonStyle(MinutesButtonStyle())
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
        .buttonStyle(MinutesButtonStyle(kind: .destructiveSecondary))
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
            }
        }.navigationBarTitleDisplayMode(.inline).tint(MinutesStyle.accent)
    }

    private func detailsPage(_ variant: ModelCatalogVariant) -> some View {
        ScrollViewReader { proxy in
            modelDetails(variant)
                .screenshotScroll(proxy, ready: screenshotDetailsPrepared)
        }
        .screenshotReady(screenshotDetailsPrepared)
        .task {
            #if DEBUG
            if AppScreenshotFixture.scene != nil {
                await Task.yield()
                screenshotDetailsPrepared = true
            }
            #endif
        }
    }

    private func modelDetails(_ variant: ModelCatalogVariant) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ModelDisplay.name(variant.manifest)).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("models.details.title")
                    Text(variant.detail).foregroundStyle(.secondary)
                    Text(repositoryName(variant.manifest)).font(.footnote).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("models.repository.title")
                    MinutesActions { modelActions(variant) }.padding(.top, 4)
                }.padding(.vertical, 8)
            }.screenshotAnchor("models.repository")
            feedbackSection
            if let context = variant.contextWindow {
                Section("Context window") {
                    MinutesLabeledValue(title: "Maximum context", value: "\(context.maximumTokens.formatted()) tokens")
                        .accessibilityIdentifier("models.details.context")
                    MinutesLabeledValue(title: "Summary output limit", value: "\(context.outputTokenLimit.formatted()) tokens")
                        .accessibilityIdentifier("models.details.output")
                    Text("Used automatically for summaries and answers. Includes the input and generated response.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("The summary output budget is reserved within this context. Responses can finish earlier.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let url = variant.contextSourceURL {
                        Link("Publisher context specifications", destination: url).frame(minHeight: 44)
                    }
                }
            }
            Section {
                MinutesLabeledValue(title: "Download size", value: bytes(ModelBrowserController.downloadBytes(variant.manifest)))
                MinutesLabeledValue(title: "Free storage", value: bytes(controller.resources.freeDiskBytes))
                Text("Installation temporarily needs up to twice the download size. Model memory requirements are additional and depend on your iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !busy, controller.installedManifest(for: variant.manifest) == nil, !controller.canDownload(variant) {
                    Text("Not enough free storage for this download. Remove another model and try again.")
                        .font(.callout).foregroundStyle(MinutesStyle.recording)
                }
            } header: {
                Text("Download & storage").accessibilityIdentifier("models.download.heading")
            }
            .screenshotAnchor("models.download")
            Section {
                MinutesLabeledValue(title: "Format", value: ModelDisplay.engine(variant.manifest))
                MinutesLabeledValue(title: "License", value: variant.manifest.licenseIdentifier)
                MinutesLabeledValue(title: "Runtime", value: variant.manifest.runtimeVersion)
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
                DisclosureGroup(isExpanded: $attributionExpanded) {
                    Text(variant.manifest.licenseNotice).font(.footnote).textSelection(.enabled)
                        .accessibilityIdentifier("models.license.notice")
                } label: {
                    // Identify the toggle label, not the container: a container
                    // identifier can replace the expanded notice's identifier.
                    Text("Attribution & terms").accessibilityIdentifier("models.license.open")
                }
                .screenshotAnchor("models.card")
                Link("View publisher repository", destination: variant.manifest.upstreamRepository)
                    .frame(minHeight: 44)
            } header: {
                Text("Source & license").accessibilityIdentifier("models.source.heading")
            }
            .screenshotAnchor("models.source")
        }.minutesList().navigationTitle("Model details")
    }

    private var transferPage: some View {
        List {
            if let manifest = controller.transferManifest {
                Section {
                    Text(ModelDisplay.name(manifest)).font(.headline)
                }
            }
            if let progress = controller.downloadProgress {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(stageTitle(progress.stage)).font(.title2.weight(.semibold))
                            .accessibilityIdentifier("models.download.stage")
                        Text((progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                            .formatted(.percent.precision(.fractionLength(0))))
                            .font(.largeTitle.weight(.semibold)).monospacedDigit()
                            .accessibilityIdentifier("models.download.percent")
                        ProgressView(value: progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                            .accessibilityIdentifier("models.download.progress")
                        Text("\(bytes(progress.overallCompletedBytes)) of \(bytes(progress.overallTotalBytes))")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("models.download.bytes")
                        if controller.isDownloading {
                            Button("Pause download") { controller.cancelDownload() }
                                .buttonStyle(MinutesButtonStyle(kind: .secondary))
                                .accessibilityIdentifier("models.download.pause")
                        } else if progress.stage == .paused || progress.stage == .failed {
                            Button("Resume download") { controller.resumeDownload() }
                                .buttonStyle(MinutesButtonStyle())
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
                Section { MinutesActions { modelActions(variant) } }
            }
            feedbackSection
        }.minutesList().navigationTitle("Model transfer").screenshotReady(true)
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
        let purpose = manifest.purpose == .speechRecognition ? "speech" : "summary"
        for family in families {
            if let variant = family.variants.first(where: { $0.matches(manifest) }) {
                return "\(purpose) model \(family.title) \(variant.title)"
            }
        }
        return "\(purpose) model \(ModelDisplay.name(manifest))"
    }
    private func stageTitle(_ stage: ModelTransferStage) -> String {
        switch stage {
        case .preparing: "Preparing download"
        case .downloading: "Downloading"
        case .verifying: "Verifying files"
        case .installing: "Installing"
        case .completed: "Ready to use"
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
