import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ModelDisplay {
    static func name(_ manifest: ModelManifest) -> String {
        if let pack = try? ParakeetModelPack.configuration(for: manifest) {
            return pack.decoderContract == "parakeet-tdt-v3" ? "Parakeet TDT v3" : "Parakeet TDT v2"
        }
        return manifest.upstreamRepository.lastPathComponent.replacingOccurrences(of: "-", with: " ")
    }
    static func engine(_ manifest: ModelManifest) -> String {
        switch manifest.runtimeVersion {
        case ParakeetCoreMLModel.runtimeVersion, ParakeetModelPack.runtimeVersion: "Core ML"
        case "llama.cpp-b5046": "GGUF"
        default: manifest.runtimeVersion
        }
    }
}

enum ModelScreen: Hashable, Identifiable {
    case repository, lookup, source, compatibility, requirements, download, transfer, files, card, apple
    case installed(String)
    var id: Self { self }
}

/// Standalone host used by the owned native UI fixture. Production model setup
/// lives in Settings or a contextual setup sheet, using the same views.
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
    @State private var captureRoute: ModelScreen?
    @State private var showingTransfer = false
    @State private var showingPackImport = false
    @State private var showingImport = false
    @State private var importManifest: ModelManifest?
    @State private var pendingRemoval: ModelManifest?
    @State private var confirmingRemoval = false
    @State private var confirmingDiscard = false
    @State private var modelDetailsExpanded = false
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
            _modelDetailsExpanded = State(initialValue: scene == .modelsDetails)
            let route: ModelScreen?
            switch scene {
            case .modelsRepository: route = .repository
            case .modelsSource, .modelsCard: route = .source
            case .modelsCompatibility: route = .compatibility
            case .modelsRequirements: route = .requirements
            case .modelsDownload, .modelsImport: route = .download
            case .modelsDownloading, .modelsVerifying: route = .transfer
            case .modelsDetails, .modelsRemove: route = .installed("ui-model-alpha")
            default: route = nil
            }
            _captureRoute = State(initialValue: route)
        } else if controller.downloadProgress != nil {
            _captureRoute = State(initialValue: .transfer)
        }
        #endif
    }

    private var busy: Bool { controller.isWorking || controller.isInspecting || controller.isPreparingStorageCheck }
    private var installed: [ModelManifest] { controller.installed.filter { $0.purpose == purpose } }
    private var title: String { purpose == .speechRecognition ? "Speech model" : "Summary model" }
    private var selectionTitle: String { purpose == .speechRecognition ? "Use for recording" : "Use for summaries" }
    private var repositoryTitle: String {
        if let manifest = controller.repository?.parakeetManifest { return ModelDisplay.name(manifest) }
        return controller.repository?.id.rawValue.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "-", with: " ") ?? "Model"
    }

    var body: some View {
        List {
            if controller.purpose != purpose && busy {
                Section { Text("Finish the current model operation before changing model purpose.") }
            } else {
                Section("On this iPhone") {
                    ForEach(installed, id: \.modelID) { manifest in
                        NavigationLink(value: ModelScreen.installed(manifest.modelID)) {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(ModelDisplay.name(manifest)).font(.headline)
                                        .accessibilityIdentifier("models.title.\(manifest.modelID)")
                                    Text("\(controller.isEquipped(manifest) ? "Selected · " : "")\(bytes(installedBytes(manifest))) · \(ModelDisplay.engine(manifest))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if controller.isEquipped(manifest) {
                                    Image(systemName: "checkmark").foregroundStyle(MinutesStyle.accent).accessibilityLabel("Selected")
                                }
                            }.padding(.vertical, 8)
                        }
                        .accessibilityIdentifier("models.open.\(manifest.modelID)")
                    }
                    if installed.isEmpty && purpose == .speechRecognition {
                        Text("No speech model installed.").foregroundStyle(.secondary)
                            .accessibilityIdentifier("models.empty")
                    }
                    if purpose == .summary {
                        NavigationLink(value: ModelScreen.apple) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Apple Intelligence").font(.headline).accessibilityIdentifier("models.apple.title")
                                Text(controller.appleEquipped ? "Selected · Managed by iOS" : controller.appleAvailability.explanation)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("models.apple.availability")
                            }.padding(.vertical, 8)
                        }.accessibilityIdentifier("models.apple.open")
                    }
                }
                if purpose == .speechRecognition {
                    Section("Add a speech model") {
                        Button {
                            controller.loadBundledParakeetV3()
                            if controller.errorMessage == nil { captureRoute = .repository }
                        } label: { Label("Get Parakeet TDT v3", systemImage: "waveform") }
                        .frame(minHeight: 44).accessibilityIdentifier("models.parakeet.browse")
                        .disabled(busy)
                        Button("Open model pack", systemImage: "folder") { showingPackImport = true }
                            .frame(minHeight: 44).accessibilityIdentifier("models.pack.import")
                            .disabled(busy)
                    }
                }
                Section {
                    NavigationLink(value: ModelScreen.lookup) { Label("Find a repository", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("models.repository.open").disabled(busy)
                    if controller.downloadProgress != nil {
                        NavigationLink("Current transfer", value: ModelScreen.transfer)
                            .accessibilityIdentifier("models.transfer.open")
                    }
                }
                if let error = controller.errorMessage { Section { Text(error).foregroundStyle(MinutesStyle.recording) } }
            }
        }
        .minutesList().navigationTitle(title)
        .navigationDestination(for: ModelScreen.self, destination: page)
        .navigationDestination(item: $captureRoute, destination: page)
        .fileImporter(isPresented: $showingPackImport, allowedContentTypes: [.json]) { result in
            if case .success(let file) = result {
                controller.importParakeetPack(file)
                if controller.errorMessage == nil { captureRoute = .repository }
            }
        }
        .task {
            if !busy { controller.purpose = purpose }
            await controller.refresh()
            screenshotPrepared = true
        }
        .refreshable { await controller.refresh() }
        .screenshotReady(screenshotPrepared)
    }

    @ViewBuilder private func page(_ route: ModelScreen) -> some View {
        Group {
            switch route {
            case .lookup: lookupPage
            case .repository: repositoryPage
            case .source: sourcePage
            case .compatibility:
                Form { compatibilitySection }.minutesList().navigationTitle("Compatibility")
            case .requirements:
                Form {
                    requirementsSection
                    Section { NavigationLink("This iPhone") { ModelDeviceView(controller: controller) } }
                }.minutesList().navigationTitle("Requirements")
            case .download: downloadPage
            case .transfer: transferPage
            case .files: filesPage
            case .card:
                ScrollView {
                    Text(verbatim: controller.repository?.cardMarkdown ?? "Model card unavailable.")
                        .font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .accessibilityIdentifier("models.card.content")
                }.background(MinutesStyle.background).navigationTitle("Model card")
            case .apple: applePage
            case .installed(let id):
                if let manifest = installed.first(where: { $0.modelID == id }) { installedPage(manifest) }
                else {
                    MinutesEmptyState(title: "Model removed", symbol: "internaldrive",
                                      detail: "Your meetings stay on this iPhone.")
                        .background(MinutesStyle.background)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(MinutesStyle.accent)
        .screenshotReady(true)
    }

    private var lookupPage: some View {
        Form {
            Section {
                TextField("owner/repository or URL", text: $controller.repositoryInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .submitLabel(.search).accessibilityLabel("Hugging Face repository")
                    .onSubmit { inspect() }
                Button { inspect() } label: {
                    if controller.isInspecting { ProgressView("Reading repository…") }
                    else { Label("Look up repository", systemImage: "magnifyingglass") }
                }.frame(minHeight: 44)
                    .disabled(busy || controller.repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Hugging Face repository")
            } footer: {
                Text("Public repositories only.")
            }
            if let error = controller.errorMessage { Section { Text(error).foregroundStyle(MinutesStyle.recording) } }
        }.minutesList().navigationTitle("Add a model")
    }

    private var repositoryPage: some View {
        Form {
            Section {
                Label(repositoryTitle, systemImage: purpose == .speechRecognition ? "waveform" : "sparkles")
                    .font(.title2.weight(.semibold)).accessibilityIdentifier("models.repository.title")
                if let resource = controller.resourceAssessment {
                    Text("\(bytes(resource.requiredDiskBytes)) · \(purpose == .speechRecognition ? "Core ML" : "GGUF")")
                        .foregroundStyle(.secondary)
                }
                if !variants.isEmpty {
                    Picker("Model file", selection: $controller.selectedFileName) {
                        Text("Choose a file").tag(Optional<String>.none)
                        ForEach(variants, id: \.fileName) { file in
                            Text("\(file.fileName) · \(bytes(file.byteCount))").tag(Optional(file.fileName))
                        }
                    }.disabled(busy).accessibilityIdentifier("models.variant")
                }
            }
            Section {
                NavigationLink("Compatibility", value: ModelScreen.compatibility)
                NavigationLink("Requirements", value: ModelScreen.requirements)
                NavigationLink("Source & license", value: ModelScreen.source)
            }
            Section {
                NavigationLink("Download or import", value: ModelScreen.download)
                    .disabled(!controller.canDownload)
                if let status = controller.compatibility, status.status != .supported {
                    Label(compatibilityTitle(status.status), systemImage: "info.circle").foregroundStyle(.secondary)
                }
                if let resource = controller.resourceAssessment, resource.status != .sufficient {
                    Text(resourceTitle(resource.status)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }.minutesList().navigationTitle("Model")
    }

    private var sourcePage: some View {
        Form {
            if let repository = controller.repository {
                Section("Repository") {
                    Text(repository.id.rawValue).font(.headline).textSelection(.enabled)
                    LabeledContent("License", value: repository.licenseIdentifier ?? "Unknown")
                    LabeledContent("Task", value: repository.pipelineTag ?? "Unknown")
                    LabeledContent("Architecture", value: repository.modelType ?? repository.architectures.joined(separator: ", "))
                    LabeledContent("Library", value: repository.libraryName ?? "Unknown")
                }
                Section("Pinned revision") {
                    Text(repository.revision).font(.footnote.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("models.repository.revision")
                }
                Section {
                    NavigationLink("Read model card", value: ModelScreen.card)
                        .accessibilityIdentifier("models.card.open").disabled(repository.cardMarkdown == nil)
                    NavigationLink("Model files", value: ModelScreen.files)
                }
                if let notice = repository.parakeetManifest?.licenseNotice {
                    Section("Attribution") { Text(notice).font(.footnote).textSelection(.enabled) }
                }
            }
        }.minutesList().navigationTitle("Source & license")
    }

    @ViewBuilder private var compatibilitySection: some View {
        if let result = controller.compatibility {
            Section {
                Label(compatibilityTitle(result.status), systemImage: result.status == .supported ? "checkmark.shield" : "exclamationmark.circle")
                if let profile = result.profile { LabeledContent("Engine", value: profileTitle(profile)) }
                ForEach(Array(result.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.callout) }
                ForEach(result.suggestedRepositories, id: \.self) { repository in
                    Button("Look up \(repository)") { controller.repositoryInput = repository; inspect() }.disabled(busy)
                }
                NavigationLink("\(result.selectedFiles.count) model files", value: ModelScreen.files)
                if let error = controller.errorMessage { Text(error).foregroundStyle(MinutesStyle.recording) }
            } header: { Text("Compatibility").accessibilityIdentifier("models.compatibility.heading") }
        }
    }

    @ViewBuilder private var requirementsSection: some View {
        if let result = controller.resourceAssessment {
            Section {
                LabeledContent("Model files", value: bytes(result.requiredDiskBytes))
                LabeledContent("Free storage", value: bytes(controller.resources.freeDiskBytes))
                LabeledContent("Estimated memory", value: ramRange(result))
                if purpose == .summary {
                    LabeledContent("Requested context", value: "\(result.requestedContextTokens.formatted()) tokens")
                    LabeledContent("Context capacity", value: result.maximumContextTokens.map { "\($0.formatted()) tokens" } ?? "Unknown")
                }
                Text(resourceTitle(result.status)).font(.callout).foregroundStyle(.secondary)
                ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Before you install").accessibilityIdentifier("models.requirements.heading") }
        }
    }

    private var downloadPage: some View {
        Form {
            Section {
                Text(repositoryTitle).font(.title2.weight(.semibold))
                LabeledContent("Model files", value: bytes(controller.resourceAssessment?.requiredDiskBytes))
                Text("Files are checked before installation.").foregroundStyle(.secondary)
            }
            Section {
                Button {
                    controller.downloadSelected()
                    showingTransfer = controller.isDownloading || controller.downloadProgress != nil
                } label: { Label("Download selected model", systemImage: "arrow.down.circle") }
                .frame(minHeight: 44).accessibilityIdentifier("models.download.selected")
                .disabled(!controller.canDownload)
                Button("Import from Files", systemImage: "folder") {
                    importManifest = controller.selectedImportManifest()
                    showingImport = importManifest != nil
                }
                .frame(minHeight: 44).accessibilityIdentifier("models.import").disabled(!controller.canDownload)
                .fileImporter(isPresented: $showingImport, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
                    guard let manifest = importManifest else { return }
                    importManifest = nil
                    if case .success(let urls) = result {
                        controller.importSelectedFiles(urls, manifest: manifest)
                        showingTransfer = controller.isImporting
                    }
                }
                Button("Remove unfinished download", role: .destructive) { confirmingDiscard = true }
                    .frame(minHeight: 44).disabled(controller.selectedImportManifest() == nil || busy)
            }
            if let error = controller.errorMessage { Section { Text(error).foregroundStyle(MinutesStyle.recording) } }
        }
        .minutesList().navigationTitle("Get model")
        .navigationDestination(isPresented: $showingTransfer) { page(.transfer) }
        .confirmationDialog("Remove partial download?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Remove download", role: .destructive) { controller.discardSelectedDownload() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Downloaded files for this model will be removed. Installed models stay available.") }
    }

    private var transferPage: some View {
        List {
            if controller.isImporting {
                Section {
                    MinutesProgress(title: "Checking selected files", detail: "Verifying this model.",
                                    cancel: controller.cancelDownload)
                }
            } else if let progress = controller.downloadProgress {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(stageTitle(progress.stage)).font(.title2.weight(.semibold))
                                .accessibilityIdentifier("models.download.stage")
                            Spacer()
                            Text((progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                                .formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit().accessibilityIdentifier("models.download.percent")
                        }
                        ProgressView(value: progress.stage == .downloading ? progress.overallFractionCompleted : progress.fractionCompleted)
                            .accessibilityIdentifier("models.download.progress")
                        Text("\(bytes(progress.overallCompletedBytes)) of \(bytes(progress.overallTotalBytes))")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("models.download.bytes")
                        if controller.isDownloading {
                            Button("Pause download") { controller.cancelDownload() }.frame(minHeight: 44)
                                .accessibilityIdentifier("models.download.pause")
                        } else if progress.stage == .paused || progress.stage == .failed {
                            Button("Resume download") { controller.downloadSelected() }.frame(minHeight: 44)
                                .disabled(!controller.canDownload).accessibilityIdentifier("models.download.resume")
                        }
                    }.padding(.vertical, 12)
                }
                Section {
                    DisclosureGroup("Transfer details", isExpanded: $transferDetails) {
                        Text("File \(progress.fileIndex) of \(progress.fileCount)").accessibilityIdentifier("models.download.file")
                        Text(progress.fileName).font(.footnote).textSelection(.enabled)
                            .accessibilityIdentifier("models.download.filename")
                        if progress.stage == .downloading {
                            Text(transferSpeed(progress.bytesPerSecond))
                                .accessibilityIdentifier("models.download.speed")
                            Text(timeRemaining(progress.remainingSeconds)).accessibilityIdentifier("models.download.remaining")
                        }
                        if progress.resumedBytes > 0 {
                            Text("Resumed \(bytes(progress.resumedBytes))").accessibilityIdentifier("models.download.resumed")
                        }
                    }.accessibilityIdentifier("models.download.details")
                }
            }
            if !controller.isWorking, let manifest = controller.selectedImportManifest(),
               controller.installed.contains(manifest) {
                Section { useButton(manifest) }
            }
            if let error = controller.errorMessage { Section { Text(error).foregroundStyle(MinutesStyle.recording) } }
            else if let message = controller.message, !controller.isWorking {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }.minutesList().navigationTitle("Model transfer")
    }

    private var filesPage: some View {
        List {
            ForEach(controller.compatibility?.selectedFiles ?? [], id: \.fileName) { file in
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.fileName).font(.subheadline).textSelection(.enabled)
                    Text("\(bytes(file.byteCount)) · \(file.sha256 == nil ? "Checksum unavailable" : "Expected checksum available")")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let digest = file.sha256 { Text(digest).font(.caption.monospaced()).textSelection(.enabled) }
                }.padding(.vertical, 6)
            }
        }.minutesList().navigationTitle("Model files")
    }

    private var applePage: some View {
        Form {
            Section {
                Label("Apple Intelligence", systemImage: "sparkles").font(.title2.weight(.semibold))
                    .accessibilityIdentifier("models.apple.title")
                Text("Managed by iOS").foregroundStyle(.secondary)
                Text(appleAvailability.explanation).accessibilityIdentifier("models.apple.availability")
                Button(controller.appleEquipped ? "Selected" : "Use Apple Intelligence") {
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
                if let error = controller.errorMessage { Text(error).foregroundStyle(MinutesStyle.recording) }
            }
        }.minutesList().navigationTitle("Apple Intelligence")
            .onAppear { appleAvailability = controller.appleAvailability }
    }

    private func installedPage(_ manifest: ModelManifest) -> some View {
        Form {
            Section {
                Text(ModelDisplay.name(manifest)).font(.title2.weight(.semibold))
                    .accessibilityIdentifier("models.title.\(manifest.modelID)")
                Text(controller.isEquipped(manifest) ? "Selected" : "Installed").foregroundStyle(.secondary)
                LabeledContent("Storage", value: bytes(installedBytes(manifest)))
                LabeledContent("Format", value: ModelDisplay.engine(manifest))
                useButton(manifest)
            }
            Section {
                DisclosureGroup("Source & files", isExpanded: $modelDetailsExpanded) {
                    Text(manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                        .font(.subheadline).textSelection(.enabled)
                    Text(manifest.runtimeVersion).font(.footnote).accessibilityIdentifier("models.runtime.\(manifest.modelID)")
                    Text(manifest.revision).font(.caption.monospaced()).textSelection(.enabled)
                    LabeledContent("License", value: manifest.licenseIdentifier)
                    DisclosureGroup("\(manifest.artifacts.count) verified files") {
                        ForEach(manifest.artifacts, id: \.fileName) {
                            Text("\($0.fileName) · \(bytes($0.byteCount))").font(.footnote).textSelection(.enabled)
                        }
                    }
                    DisclosureGroup("Attribution") { Text(manifest.licenseNotice).font(.footnote).textSelection(.enabled) }
                }.accessibilityIdentifier("models.details.\(manifest.modelID)")
            }
            Section {
                Button("Remove model…", role: .destructive) {
                    pendingRemoval = manifest; confirmingRemoval = true
                }
                .frame(minWidth: 44, minHeight: 44).disabled(busy)
                .accessibilityLabel("Remove \(modelActionIdentity(manifest))")
                .accessibilityIdentifier("models.remove.\(manifest.modelID)")
            }
            if let error = controller.errorMessage {
                Section { Text(error).foregroundStyle(MinutesStyle.recording) }
            }
        }
        .minutesList().navigationTitle("Model details")
        .confirmationDialog("Remove this model?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove model", role: .destructive) {
                guard let model = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await controller.remove(model) }
            }.accessibilityIdentifier("models.remove.confirm")
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("Your meetings stay on this iPhone. You can download the model again.") }
    }

    private func useButton(_ manifest: ModelManifest) -> some View {
        Button(controller.isEquipped(manifest) ? "Selected" : selectionTitle) {
            Task {
                await controller.equip(manifest)
                if controller.isEquipped(manifest) { onSelected?() }
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(controller.isEquipped(manifest) ? "Selected \(modelActionIdentity(manifest))" : "Use \(modelActionIdentity(manifest))")
        .accessibilityIdentifier("models.equip.\(manifest.modelID)")
        .disabled(busy || controller.isEquipped(manifest))
    }

    private func modelActionIdentity(_ manifest: ModelManifest) -> String {
        "\(manifest.purpose == .speechRecognition ? "speech" : "summary") model \(manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }
    private var variants: [HuggingFaceModelFile] {
        guard purpose == .summary else { return [] }
        return (controller.repository?.files ?? []).filter {
            let name = $0.fileName.lowercased()
            return name.hasSuffix(".gguf") && !name.contains("mmproj")
                && name.range(of: "-[0-9]{5}-of-[0-9]{5}\\.gguf$", options: .regularExpression) == nil
        }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }
    private func inspect() {
        guard !busy, !controller.repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await controller.inspect()
            if controller.repository != nil && controller.errorMessage == nil { captureRoute = .repository }
        }
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

    private func bytes(_ value: Int64?, memory: Bool = false) -> String {
        guard let value, value >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: memory ? .memory : .file)
    }

    private func installedBytes(_ manifest: ModelManifest) -> Int64? {
        var sum: Int64 = 0
        for file in manifest.artifacts {
            guard file.byteCount >= 0 else { return nil }
            let step = sum.addingReportingOverflow(file.byteCount)
            guard !step.overflow else { return nil }; sum = step.partialValue
        }
        return sum
    }

    private func ramRange(_ assessment: ModelResourceAssessment) -> String {
        guard let lower = assessment.estimatedRAMLowerBoundBytes,
              let upper = assessment.estimatedRAMUpperBoundBytes,
              lower > 0, upper >= lower else { return "Unknown" }
        return lower == upper ? "About \(bytes(lower, memory: true))"
            : "About \(bytes(lower, memory: true))–\(bytes(upper, memory: true))"
    }

    private func profileTitle(_ profile: HuggingFaceRuntimeProfile) -> String {
        switch profile {
        case .parakeetTDTCoreML: "Core ML · Parakeet TDT"
        case .llamaGGUF: "llama.cpp · GGUF"
        }
    }

    private func compatibilityTitle(_ status: HuggingFaceCompatibilityStatus) -> String {
        switch status {
        case .supported: "Format supported"
        case .plannedRuntime: "Runtime validation pending"
        case .conversionRequired: "Conversion required"
        case .unsupported: "Unsupported architecture or format"
        case .unverified: "More verification required"
        case .tooLarge: "Exceeds download limit"
        case .gated: "Public access unavailable"
        case .selectionRequired: "Choose one file variant"
        }
    }

    private func compatibilitySymbol(_ status: HuggingFaceCompatibilityStatus) -> String {
        switch status {
        case .supported: "checkmark.shield"
        case .selectionRequired: "list.bullet"
        case .gated: "lock"
        default: "exclamationmark.circle"
        }
    }

    private func resourceTitle(_ status: ModelResourceStatus) -> String {
        switch status {
        case .sufficient: "Reported resources fit."
        case .insufficientStorage: "Not enough free storage for the selected model."
        case .insufficientMemory: "Available memory is below the model estimate."
        case .caution: "Estimates fit; actual model performance still needs verification."
        case .unknown: "A resource requirement or device measurement is unknown."
        case .contextLimitExceeded: "Requested context exceeds the model limit."
        }
    }

    private func resourceColor(_ status: ModelResourceStatus) -> Color {
        switch status {
        case .insufficientStorage, .insufficientMemory, .contextLimitExceeded: .red
        case .caution, .unknown: .secondary
        case .sufficient: .primary
        }
    }
}
