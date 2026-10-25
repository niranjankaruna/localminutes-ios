import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ModelBrowserView: View {
    @Bindable var controller: ModelBrowserController
    @State private var showingCard = false
    @State private var pendingRemoval: ModelManifest?
    @State private var showingRemoval = false
    @State private var showingImport = false
    @State private var importManifest: ModelManifest?

    init(controller: ModelBrowserController) { self.controller = controller }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Model purpose", selection: $controller.purpose) {
                        Text("Speech").tag(ModelPurpose.speechRecognition)
                        Text("Summary").tag(ModelPurpose.summary)
                    }
                    .pickerStyle(.segmented)
                    .disabled(controller.isWorking)
                }

                Section("Hugging Face repository") {
                    TextField("owner/repository or Hugging Face URL", text: $controller.repositoryInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.search)
                        .accessibilityLabel("Hugging Face repository")
                        .disabled(controller.isInspecting || controller.isWorking)
                        .onSubmit { inspect() }
                    Button { inspect() } label: {
                        if controller.isInspecting { ProgressView("Reading repository…") }
                        else { Label("Look up repository", systemImage: "magnifyingglass") }
                    }
                    .disabled(controller.repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || controller.isInspecting || controller.isWorking)
                    Text("Lookup reads public metadata and the model card. Choose a file and review compatibility before downloading weights.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let repository = controller.repository {
                    repositorySection(repository)
                    if !variants.isEmpty {
                        Section("File variant") {
                            Picker("Model file", selection: $controller.selectedFileName) {
                                Text("Choose a variant").tag(Optional<String>.none)
                                ForEach(variants, id: \.fileName) { file in
                                    Text(verbatim: "\(file.fileName) · \(bytes(file.byteCount))")
                                        .tag(Optional(file.fileName))
                                }
                            }
                            .disabled(controller.isWorking || controller.isInspecting)
                            Text(controller.purpose == .speechRecognition && variants.contains(where: { $0.fileName.hasSuffix(".onnx") })
                                 ? "Choose an encoder to select its matching encoder, decoder, joiner and tokens set."
                                 : "Only the selected file is downloaded; other variants stay on Hugging Face.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    compatibilitySection
                    selectedResourcesSection
                    Section {
                        Button { controller.downloadSelected() } label: {
                            Label("Download selected model", systemImage: "arrow.down.circle")
                        }
                        .disabled(!controller.canDownload || controller.isWorking || controller.isInspecting)
                        Button("Import selected model from Files") {
                            importManifest = controller.selectedImportManifest()
                            showingImport = importManifest != nil
                        }
                        .disabled(!controller.canDownload || controller.isWorking || controller.isInspecting)
                        if controller.isDownloading {
                            ProgressView(controller.message ?? "Working with model files…")
                            Button("Pause download") { controller.cancelDownload() }
                        }
                        if controller.isImporting {
                            ProgressView(controller.message ?? "Importing model…")
                            Button("Cancel import") { controller.cancelDownload() }
                        }
                        Button("Remove unfinished download", role: .destructive) { controller.discardSelectedDownload() }
                            .disabled(controller.selectedImportManifest() == nil || controller.isWorking)
                        Text("For Whisper or GGUF, select the expected file. For native Parakeet, select the folder containing all four Core ML bundles and parakeet_vocab.json.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Downloads are verified before installation. Format compatibility does not establish answer quality, speed or memory use on this iPhone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                deviceResourcesSection
                installedSection

                if let message = controller.message, !controller.isDownloading {
                    Section { Text(verbatim: message).accessibilityIdentifier("model-browser-status") }
                }
                if let error = controller.errorMessage {
                    Section("Could not complete this action") {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("model-browser-error")
                    }
                }
                Section("Action Button") {
                    Text("In iPhone Settings, choose Action Button → Shortcut → Toggle LocalMinutes Recording.")
                    Text("Locked start and two-hour recording behavior still require checks on your iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy and renewal") {
                    Text("Meeting audio and text are processed on this iPhone. Repository lookup and model downloads need internet.")
                    Text("Use a free Apple Account and refresh with iLoader every seven days. Keep the same Apple Account and bundle IDs, and install over the existing app.")
                    Text("Export important notes before renewal and verify your meetings and models afterward. Do not delete the app to refresh it.")
                    Text("Record meetings only with the participants’ consent.")
                }
                Section("About LocalMinutes") {
                    if let identity = AppBuildIdentity.current() {
                        Text(verbatim: "Version \(identity.version) (build \(identity.build))")
                            .accessibilityIdentifier("settings.appBuildIdentity")
                    } else {
                        Text("Version and build information unavailable")
                            .accessibilityIdentifier("settings.appBuildIdentity")
                    }
                }
            }
            .navigationTitle("Models")
            .task { await controller.refresh() }
            .refreshable { await controller.refresh() }
            .sheet(isPresented: $showingCard) { modelCard }
            .fileImporter(isPresented: $showingImport, allowedContentTypes: [.data, .folder],
                          allowsMultipleSelection: true) { result in
                guard let manifest = importManifest else { return }
                importManifest = nil
                if case .success(let files) = result { controller.importSelectedFiles(files, manifest: manifest) }
            }
            .confirmationDialog("Remove installed model?", isPresented: $showingRemoval,
                                titleVisibility: .visible) {
                if let manifest = pendingRemoval {
                    Button("Remove model", role: .destructive) {
                        pendingRemoval = nil
                        Task { await controller.remove(manifest) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text("The model can be downloaded again. Your meetings remain stored separately.")
            }
        }
    }

    private func inspect() {
        guard !controller.isInspecting, !controller.isWorking,
              !controller.repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await controller.inspect() }
    }

    private var variants: [HuggingFaceModelFile] {
        guard let repository = controller.repository else { return [] }
        return repository.files.filter { file in
            let name = file.fileName.lowercased()
            let basename = file.downloadURL.lastPathComponent.lowercased()
            if controller.purpose == .summary {
                return name.hasSuffix(".gguf") && !name.contains("mmproj")
                    && name.range(of: "-[0-9]{5}-of-[0-9]{5}\\.gguf$", options: .regularExpression) == nil
            }
            return (basename.hasPrefix("ggml-") && basename.hasSuffix(".bin"))
                || (name.hasPrefix("encoder-") && name.hasSuffix(".onnx"))
        }.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    private func repositorySection(_ repository: HuggingFaceModelRepository) -> some View {
        Section("Repository details") {
            Text(verbatim: repository.id.rawValue).font(.headline).textSelection(.enabled)
            LabeledContent("License", value: repository.licenseIdentifier ?? "Unknown — review required")
            LabeledContent("Task", value: repository.pipelineTag ?? "Unknown")
            LabeledContent("Architecture", value: repository.modelType
                ?? (repository.architectures.isEmpty ? "Unknown" : repository.architectures.joined(separator: ", ")))
            LabeledContent("Library", value: repository.libraryName ?? "Unknown")
            VStack(alignment: .leading, spacing: 4) {
                Text("Pinned revision").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: repository.revision).font(.caption.monospaced()).textSelection(.enabled)
            }
            Button("Read full model card") { showingCard = true }
                .disabled(repository.cardMarkdown == nil)
            if repository.cardMarkdown == nil {
                Text("No public model card was available at this revision.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var compatibilitySection: some View {
        if let result = controller.compatibility {
            Section("Engine compatibility") {
                Label(compatibilityTitle(result.status), systemImage: compatibilitySymbol(result.status))
                if let profile = result.profile {
                    LabeledContent("Engine", value: profileTitle(profile))
                }
                ForEach(Array(result.reasons.enumerated()), id: \.offset) { _, reason in
                    Text(verbatim: reason).font(.callout)
                }
                if !result.suggestedRepositories.isEmpty {
                    ForEach(result.suggestedRepositories, id: \.self) { repository in
                        Button("Look up " + repository) {
                            controller.repositoryInput = repository
                            inspect()
                        }.disabled(controller.isWorking || controller.isInspecting)
                    }
                }
                if !result.selectedFiles.isEmpty {
                    ForEach(result.selectedFiles, id: \.fileName) { file in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: file.fileName).font(.caption).textSelection(.enabled)
                            Text("\(bytes(file.byteCount)) · \(file.sha256 == nil ? "SHA-256 unavailable" : "Expected SHA-256 available")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var selectedResourcesSection: some View {
        if let result = controller.resourceAssessment {
            Section("Selected model requirements") {
                LabeledContent("Model files", value: bytes(result.requiredDiskBytes))
                LabeledContent("Estimated RAM", value: ramRange(result))
                if controller.purpose == .summary {
                    LabeledContent("Requested context", value: "\(result.requestedContextTokens.formatted()) tokens")
                    LabeledContent("Context capacity", value: result.maximumContextTokens.map { "\($0.formatted()) tokens" } ?? "Unknown")
                }
                Text(resourceTitle(result.status))
                    .foregroundStyle(resourceColor(result.status))
                ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deviceResourcesSection: some View {
        Section("This iPhone now") {
            LabeledContent("Free storage", value: bytes(controller.resources.freeDiskBytes))
            LabeledContent("Total RAM", value: bytes(controller.resources.totalMemoryBytes, memory: true))
            LabeledContent("Available to this app", value: bytes(controller.resources.availableAppMemoryBytes, memory: true))
            Text("Available memory changes as the phone runs. Model estimates are guidance; actual use can be higher.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var installedSection: some View {
        let installed = controller.installed.filter { $0.purpose == controller.purpose }
        return Section(controller.purpose == .speechRecognition ? "Installed speech models" : "Installed summary models") {
            if installed.isEmpty {
                Text("No verified model installed for this purpose.").foregroundStyle(.secondary)
            }
            ForEach(installed.map { InstalledModelRow(manifest: $0) }) { entry in
                let manifest = entry.manifest
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                        .font(.headline).textSelection(.enabled)
                    ForEach(manifest.artifacts, id: \.fileName) { artifact in
                        Text(verbatim: "\(artifact.fileName) · \(bytes(artifact.byteCount))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(bytes(installedBytes(manifest))) · \(manifest.runtimeVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if controller.isEquipped(manifest) {
                            Label("Equipped", systemImage: "checkmark.circle.fill")
                                .font(.callout).foregroundStyle(.green)
                        } else {
                            Button("Equip") { Task { await controller.equip(manifest) } }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Equip \(modelActionIdentity(manifest))")
                                .disabled(controller.isWorking || controller.isInspecting)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            pendingRemoval = manifest; showingRemoval = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove \(modelActionIdentity(manifest))")
                        .disabled(controller.isWorking || controller.isInspecting)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func modelActionIdentity(_ manifest: ModelManifest) -> String {
        let purpose = manifest.purpose == .speechRecognition ? "speech" : "summary"
        let repository = manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(purpose) model \(repository)"
    }

    private var modelCard: some View {
        NavigationStack {
            ScrollView {
                // Verbatim Text treats card code/HTML/images as inert content.
                Text(verbatim: controller.repository?.cardMarkdown ?? "Model card unavailable.")
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("Model card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingCard = false } } }
        }
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
        case .parakeetTDTCoreML: "Core ML + Swift TDT · Parakeet v2"
        case .streamingZipformerONNX: "sherpa-onnx · streaming Zipformer"
        case .whisperGGML: "whisper.cpp · Whisper GGML"
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
        case .notImplemented: "Assessment unavailable"
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
        case .notImplemented: "Resource comparison unavailable."
        }
    }

    private func resourceColor(_ status: ModelResourceStatus) -> Color {
        switch status {
        case .insufficientStorage, .insufficientMemory, .contextLimitExceeded: .red
        case .caution, .unknown, .notImplemented: .secondary
        case .sufficient: .primary
        }
    }
}

private struct InstalledModelRow: Identifiable {
    let manifest: ModelManifest
    var id: String { manifest.modelID + "@" + manifest.revision }
}
