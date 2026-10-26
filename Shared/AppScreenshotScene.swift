#if DEBUG && os(iOS)
import Foundation

enum AppScreenshotScene: String, CaseIterable {
    case recordIdle = "record_idle"
    case recordModelRequired = "record_speech_model_required"
    case meetingsEmpty = "meetings_empty"
    case meetingsHistory = "meetings_history"
    case meetingsActions = "meetings_actions"
    case meetingsBackup = "meetings_backup_ready"
    case meetingsRestore = "meetings_restore_picker"
    case meetingsSearch = "meetings_search"
    case meetingNotes = "meeting_notes"
    case meetingTranscript = "meeting_transcript"
    case meetingTranscriptSearch = "meeting_transcript_search"
    case meetingSummary = "meeting_summary"
    case meetingSummaryReset = "meeting_summary_reset_confirmation"
    case meetingAnswers = "meeting_questions_and_answers"
    case meetingExport = "meeting_export"
    case meetingShare = "meeting_share_sheet"
    case meetingDelete = "meeting_delete_confirmation"
    case meetingNoTranscript = "meeting_no_transcript"
    case meetingNoSummary = "meeting_no_summary"
    case meetingModelRequired = "meeting_summary_model_required"
    case modelsSpeech = "models_speech"
    case modelsSummary = "models_summary"
    case modelsStorage = "models_storage_check"
    case modelsAbout = "models_about"
    case modelsDevice = "models_device"
    case modelsRepository = "models_parakeet_repository"
    case modelsSource = "models_parakeet_source"
    case modelsCompatibility = "models_parakeet_compatibility"
    case modelsRequirements = "models_parakeet_requirements"
    case modelsDownload = "models_parakeet_download"
    case modelsImport = "models_import_picker"
    case modelsPack = "models_pack_picker"
    case modelsInstalled = "models_installed_summary"
    case modelsDetails = "models_installed_details"
    case modelsRemove = "models_remove_confirmation"
    case modelsDownloading = "models_downloading"
    case modelsVerifying = "models_verifying"
    case modelsCard = "models_model_card"
    case recordActive = "record_active"
    case recordTranscript = "record_live_transcript"
    case recordNotes = "record_live_notes"

    var isMeeting: Bool { rawValue.hasPrefix("meeting_") }
    var isHistory: Bool { rawValue.hasPrefix("meetings_") }
    var isModels: Bool { rawValue.hasPrefix("models_") }
    var isRecord: Bool { rawValue.hasPrefix("record_") }
    var isRecording: Bool { [.recordActive, .recordTranscript, .recordNotes].contains(self) }
    var isEmptyMeeting: Bool { [.meetingNoTranscript, .meetingNoSummary, .meetingModelRequired].contains(self) }
    var usesModelFixture: Bool {
        [.modelsInstalled, .modelsDetails, .modelsRemove, .modelsDownloading, .modelsVerifying, .modelsCard].contains(self)
    }
    var usesRepository: Bool {
        [.modelsRepository, .modelsSource, .modelsCompatibility, .modelsRequirements,
         .modelsDownload, .modelsImport, .modelsCard].contains(self)
    }
    var usesSummaryModels: Bool {
        [.modelsSummary, .modelsStorage, .modelsAbout, .modelsDevice, .modelsInstalled,
         .modelsDetails, .modelsRemove, .modelsDownloading, .modelsVerifying].contains(self)
    }
    var anchor: String {
        switch self {
        case .recordIdle: "record.controls"
        case .recordModelRequired: "record.status"
        case .recordActive: "record.progress"
        case .recordTranscript: "record.transcript"
        case .recordNotes: "record.notes"
        case .meetingsEmpty, .meetingsHistory, .meetingsActions, .meetingsRestore,
             .meetingsSearch: "history.top"
        case .meetingsBackup: "history.backup"
        case .meetingNotes: "meeting.notes"
        case .meetingTranscript, .meetingTranscriptSearch, .meetingNoTranscript: "meeting.transcript"
        case .meetingSummary, .meetingNoSummary: "meeting.summary"
        case .meetingSummaryReset: "meeting.summary.reset"
        case .meetingModelRequired: "meeting.intelligence"
        case .meetingAnswers: "meeting.answers"
        case .meetingExport, .meetingShare: "meeting.export"
        case .meetingDelete: "meeting.delete"
        case .modelsSpeech, .modelsSummary, .modelsPack: "models.top"
        case .modelsStorage: "models.storage"
        case .modelsAbout: "models.about"
        case .modelsDevice: "models.device"
        case .modelsRepository: "models.repository"
        case .modelsSource: "models.source"
        case .modelsCard: "models.card"
        case .modelsCompatibility: "models.compatibility"
        case .modelsRequirements: "models.requirements"
        case .modelsDownload, .modelsImport: "models.download"
        case .modelsInstalled, .modelsDetails, .modelsRemove: "models.installed"
        case .modelsDownloading, .modelsVerifying: "models.progress"
        }
    }

    // Only presentation actions; screen navigation and data setup happen in the app.
    var actions: [String] {
        switch self {
        case .meetingsActions: ["meeting.history.actions"]
        case .meetingsRestore: ["meeting.history.actions", "meeting.history.backup.restore"]
        case .meetingSummaryReset: ["meeting.summary.reset"]
        case .meetingShare: ["meeting.export.text"]
        case .meetingDelete: ["meeting.delete"]
        case .modelsImport: ["models.import"]
        case .modelsPack: ["models.pack.import"]
        case .modelsRemove: ["models.remove.ui-model-alpha"]
        case .modelsCard: ["models.card.open"]
        default: []
        }
    }
    var target: String {
        switch self {
        case .recordIdle: "recording.start"
        case .recordModelRequired: "recording.modelRequired"
        case .recordActive: "recording.elapsed"
        case .recordTranscript: "recording.liveTranscript.20000000-0000-0000-0000-000000000001"
        case .recordNotes: "meeting.notes.editor"
        case .meetingsEmpty: "meeting.history.empty"
        case .meetingsHistory, .meetingsSearch: "meeting.history.title.10000000-0000-0000-0000-000000000001"
        case .meetingsActions: "meeting.history.backup.create"
        case .meetingsBackup: "meeting.history.backup.share"
        case .meetingsRestore, .modelsImport, .modelsPack: "system.filePicker"
        case .meetingNotes: "meeting.notes.editor"
        case .meetingTranscript, .meetingTranscriptSearch: "meeting.transcript.text.20000000-0000-0000-0000-000000000002"
        case .meetingSummary: "meeting.generatedSummary.editor"
        case .meetingSummaryReset: "meeting.summary.reset.confirm"
        case .meetingAnswers: "meeting.qa.answer.editor.30000000-0000-0000-0000-000000000002"
        case .meetingExport: "meeting.export.markdown"
        case .meetingShare: "system.shareSheet"
        case .meetingDelete: "meeting.delete.confirm"
        case .meetingNoTranscript: "meeting.transcript.empty"
        case .meetingNoSummary: "meeting.generatedSummary.generate"
        case .meetingModelRequired: "meeting.intelligence.modelRequired"
        case .modelsSpeech: "models.parakeet.browse"
        case .modelsSummary: "models.apple.availability"
        case .modelsStorage: "settings.storageAudit.share"
        case .modelsAbout: "settings.appBuildIdentity"
        case .modelsDevice: "models.device.availableMemory"
        case .modelsRepository: "models.repository.title"
        case .modelsSource: "models.repository.revision"
        case .modelsCompatibility: "models.compatibility.heading"
        case .modelsRequirements: "models.requirements.heading"
        case .modelsDownload: "models.download.selected"
        case .modelsInstalled: "models.title.ui-model-alpha"
        case .modelsDetails: "models.runtime.ui-model-alpha"
        case .modelsRemove: "models.remove.confirm"
        case .modelsDownloading: "models.download.resumed"
        case .modelsVerifying: "models.download.filename"
        case .modelsCard: "models.card.content"
        }
    }
}
#endif
