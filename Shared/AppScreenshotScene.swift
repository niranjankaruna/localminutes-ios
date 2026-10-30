#if DEBUG && os(iOS)
import Foundation

/// One capture contract, consumed by the native runner and the download script.
/// JSON literals keep categories, visible targets and presentation checks in sync.
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
    case modelsDownload = "models_parakeet_download"
    case modelsInstalled = "models_installed_summary"
    case modelsDetails = "models_installed_details"
    case modelsRemove = "models_remove_confirmation"
    case modelsDownloading = "models_downloading"
    case modelsVerifying = "models_verifying"
    case modelsCard = "models_model_card"
    case recordActive = "record_active"
    case recordTranscript = "record_live_transcript"
    case recordNotes = "record_live_notes"
    case recordPreparing = "record_preparing"
    case recordStopping = "record_stopping"
    case recordListening = "record_listening"
    case recordCatchingUp = "record_catching_up"
    case recordMicrophoneDenied = "record_microphone_denied"
    case recordCaptureFailure = "record_capture_failure"
    case recordStorageFull = "record_storage_full"
    case recordPermissions = "record_permissions"
    case recordPermissionsDenied = "record_permissions_denied"
    case recordPermissionsAllowed = "record_permissions_allowed"
    case recordActivitiesDisabled = "record_live_activities_disabled"
    case recordPermissionPrompt = "record_microphone_prompt"
    case recordPrivacy = "record_privacy"
    case recordPrivacyDetails = "record_privacy_details"
    case meetingsNoResults = "meetings_no_results"
    case meetingsBackupPreparing = "meetings_backup_preparing"
    case meetingsBackupFailure = "meetings_backup_failure"
    case meetingsRestoreConfirmation = "meetings_restore_confirmation"
    case meetingsRestoreFailure = "meetings_restore_failure"
    case meetingsDelete = "meetings_delete_confirmation"
    case meetingsReport = "meetings_recording_report"
    case meetingActions = "meeting_actions"
    case meetingRename = "meeting_rename"
    case meetingNotesEmpty = "meeting_notes_empty"
    case meetingNotesEditor = "meeting_notes_editor"
    case meetingNotesSaveFailure = "meeting_notes_save_failure"
    case meetingSummaryEditor = "meeting_summary_editor"
    case meetingSummaryDetails = "meeting_summary_details"
    case meetingSummarySources = "meeting_summary_sources"
    case meetingSummaryDelete = "meeting_summary_delete_confirmation"
    case meetingSummaryGenerating = "meeting_summary_generating"
    case meetingSummaryCancelling = "meeting_summary_cancelling"
    case meetingSummaryFailure = "meeting_summary_failure"
    case meetingSummaryConflict = "meeting_summary_edit_conflict"
    case meetingSummaryReplace = "meeting_summary_replace_confirmation"
    case meetingQuestionsEmpty = "meeting_questions_empty"
    case meetingQuestionComposer = "meeting_question_composer"
    case meetingAnswerEditor = "meeting_answer_editor"
    case meetingAnswerSources = "meeting_answer_sources"
    case meetingAnswerConflict = "meeting_answer_edit_conflict"
    case meetingAnswerReplace = "meeting_answer_replace_confirmation"
    case meetingExportMarkdown = "meeting_export_markdown"
    case meetingExportUnsaved = "meeting_export_unsaved"
    case modelsSpeechVariants = "models_speech_variants"
    case modelsSummaryVariants = "models_summary_variants"
    case modelsSummaryDetails = "models_summary_details"
    case modelsSummaryContext = "models_summary_context"
    case modelsFiles = "models_source_files"
    case modelsTransferDetails = "models_transfer_details"
    case modelsPaused = "models_download_paused"
    case modelsFailed = "models_download_failed"
    case modelsInstalling = "models_installing"
    case modelsCompleted = "models_download_completed"
    case modelsSelected = "models_selected"
    case modelsStorageRequired = "models_storage_required"
    case settingsHome = "settings_home"
    case settingsPrivacy = "settings_privacy"
    case settingsPermissions = "settings_permissions"
    case settingsStorageFailure = "settings_storage_failure"
    case activityRecording = "activity_recording"
    case activityFinished = "activity_finished"
    case activityInterrupted = "activity_interrupted"
    case meetingsLoading = "meetings_loading"
    case meetingsFailure = "meetings_failure"
    case meetingsRestoring = "meetings_restoring"
    case meetingLoading = "meeting_loading"
    case meetingTranscriptNoResults = "meeting_transcript_no_results"
    case meetingTranscriptRecovering = "meeting_transcript_recovering"
    case meetingSummaryStructured = "meeting_summary_structured"
    case meetingSummaryEdited = "meeting_summary_edited"
    case meetingSummaryPaused = "meeting_summary_paused"
    case meetingAnswerGenerating = "meeting_answer_generating"
    case meetingAnswerFailure = "meeting_answer_failure"
    case meetingExportFailure = "meeting_export_failure"
    case settingsStoragePreparing = "settings_storage_preparing"
    case modelsPreparing = "models_download_preparing"
    case modelsNoTransfer = "models_transfer_empty"
    case modelsFailure = "models_failure"
    case launchScreen = "launch_screen"
    case recordModelSetup = "record_model_setup"
    case meetingModelSetup = "meeting_model_setup"

    var specification: AppScreenshotSpecification { Self.specifications[self]! }
    var isMeeting: Bool { specification.host == "meeting" }
    var isHistory: Bool { specification.host == "history" }
    var isModels: Bool { rawValue.hasPrefix("models_") }
    var isSettings: Bool { specification.host == "settings" }
    var isRecord: Bool { specification.host == "record" }
    var isActivity: Bool { specification.host == "activity" }
    var isLaunch: Bool { specification.host == "launch" }
    var isRecording: Bool { [.recordActive, .recordTranscript, .recordNotes, .recordListening, .recordCatchingUp].contains(self) }
    var usesRecordingProjection: Bool {
        isRecording || [.recordPreparing, .recordStopping, .recordMicrophoneDenied, .recordCaptureFailure, .recordStorageFull].contains(self)
    }
    var isEmptyMeeting: Bool { [.meetingNoTranscript, .meetingNoSummary, .meetingModelRequired].contains(self) }
    var usesModelFixture: Bool { specification.host == "model" }
    var usesSummaryModels: Bool { specification.summaryModels }
    var anchor: String { specification.anchor }
    var actions: [String] { specification.actions }
    var target: String { specification.required[0] }

    private static let specifications: [Self: AppScreenshotSpecification] = Dictionary(uniqueKeysWithValues: allCases.map {
        ($0, try! JSONDecoder().decode(AppScreenshotSpecification.self, from: Data($0.specificationJSON.utf8)))
    })

    private var specificationJSON: String {
        switch self {
        case .recordIdle: #"{"category":"recording","required":["recording.start","recording.elapsed"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordModelRequired: #"{"category":"recording","required":["recording.modelRequired"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .meetingsEmpty: #"{"category":"library","required":["meeting.history.empty"],"actions":[],"anchor":"","presentation":"screen","host":"history","summaryModels":false,"expectedText":{"meeting.history.empty":"No meetings yet"}}"#
        case .meetingsHistory: #"{"category":"library","required":["meeting.history.row.10000000-0000-0000-0000-000000000001"],"actions":[],"anchor":"","presentation":"screen","host":"history","summaryModels":false}"#
        case .meetingsActions: #"{"category":"library","required":["meeting.history.backup.create","meeting.history.backup.restore"],"actions":["meeting.history.actions"],"anchor":"","presentation":"menu","host":"history","summaryModels":false}"#
        case .meetingsBackup: #"{"category":"library","required":["meeting.history.backup.share","system.done"],"actions":[],"anchor":"","presentation":"sheet","host":"history","summaryModels":false}"#
        case .meetingsRestore: #"{"category":"library","required":["system.filePicker"],"actions":["meeting.history.actions","meeting.history.backup.restore"],"anchor":"","presentation":"systemSheet","host":"history","summaryModels":false}"#
        case .meetingsSearch: #"{"category":"library","required":["meeting.history.row.10000000-0000-0000-0000-000000000001"],"actions":[],"anchor":"","presentation":"screen","host":"history","summaryModels":false}"#
        case .meetingNotes: #"{"category":"notes","required":["meeting.notes.content","meeting.notes.edit"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingTranscript: #"{"category":"transcript","required":["meeting.transcript.search","meeting.transcript.segment.20000000-0000-0000-0000-000000000002"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingTranscriptSearch: #"{"category":"transcript","required":["meeting.transcript.search","meeting.transcript.segment.20000000-0000-0000-0000-000000000002"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummary: #"{"category":"summary","required":["meeting.generatedSummary.content","meeting.summary.edit"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummaryReset: #"{"category":"summary","required":["meeting.summary.reset.confirm","system.cancel"],"actions":["meeting.summary.options","meeting.summary.reset"],"anchor":"","presentation":"confirmation","host":"meeting","summaryModels":false,"alertTitle":"Start a fresh summary?"}"#
        case .meetingAnswers: #"{"category":"questions","required":["meeting.qa.answer.content.30000000-0000-0000-0000-000000000002","meeting.qa.question"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingExport: #"{"category":"sharing","required":["meeting.export.format","meeting.export.text","meeting.intelligence.share","system.done"],"actions":[],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingShare: #"{"category":"sharing","required":["system.shareSheet"],"actions":["meeting.export.text"],"anchor":"","presentation":"systemSheet","host":"meeting","summaryModels":false}"#
        case .meetingDelete: #"{"category":"library","required":["meeting.delete.confirm","system.cancel"],"actions":["meeting.actions","meeting.delete"],"anchor":"","presentation":"confirmation","host":"meeting","summaryModels":false,"alertTitle":"Delete this meeting?"}"#
        case .meetingNoTranscript: #"{"category":"transcript","required":["meeting.transcript.empty"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false,"expectedText":{"meeting.transcript.empty":"Transcript unavailable"}}"#
        case .meetingNoSummary: #"{"category":"summary","required":["meeting.generatedSummary.generate"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingModelRequired: #"{"category":"summary","required":["meeting.intelligence.modelRequired","meeting.intelligence.chooseModel"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .modelsSpeech: #"{"category":"models","required":["models.family.parakeet-v2","models.family.parakeet-v3"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsSummary: #"{"category":"models","required":["models.family.qwen25"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":true}"#
        case .modelsStorage: #"{"category":"settings","required":["settings.storageAudit.ready","settings.storageAudit.share"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsAbout: #"{"category":"settings","required":["settings.appBuildIdentity"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsDevice: #"{"category":"settings","required":["models.device.heading","models.device.availableMemory"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsRepository: #"{"category":"parakeet","required":["models.details.title","models.repository.title"],"actions":[],"anchor":"models.repository","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsSource: #"{"category":"parakeet","required":["models.source.heading","models.license.open"],"actions":[],"anchor":"models.source","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsDownload: #"{"category":"parakeet","required":["models.download.heading"],"actions":[],"anchor":"models.download","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsInstalled: #"{"category":"installed-models","required":["models.title.ui-model-alpha","models.equip.ui-model-alpha","models.remove.ui-model-alpha"],"actions":[],"anchor":"ui-model-alpha","presentation":"screen","host":"model","summaryModels":true}"#
        case .modelsDetails: #"{"category":"installed-models","required":["models.source.heading","models.runtime.ui-model-alpha"],"actions":[],"anchor":"models.source","presentation":"screen","host":"model","summaryModels":true}"#
        case .modelsRemove: #"{"category":"installed-models","required":["models.remove.confirm","system.cancel"],"actions":["models.remove.ui-model-alpha"],"anchor":"ui-model-alpha","presentation":"confirmation","host":"model","summaryModels":true,"alertTitle":"Remove this model?"}"#
        case .modelsDownloading: #"{"category":"downloads","required":["models.download.stage","models.download.progress","models.download.bytes"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Downloading"}}"#
        case .modelsVerifying: #"{"category":"downloads","required":["models.download.stage","models.download.progress","models.download.bytes"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Verifying files"}}"#
        case .modelsCard: #"{"category":"parakeet","required":["models.license.open","models.license.notice"],"actions":[],"anchor":"models.card","presentation":"screen","host":"settings","summaryModels":false}"#
        case .recordActive: #"{"category":"recording","required":["recording.elapsed","recording.stop","recording.content.tabs"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordTranscript: #"{"category":"recording","required":["recording.elapsed","recording.stop","recording.liveTranscript.20000000-0000-0000-0000-000000000001"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordNotes: #"{"category":"recording","required":["recording.stop","meeting.notes.editor"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordPreparing: #"{"category":"recording","required":["recording.preparing","recording.stop"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordStopping: #"{"category":"recording","required":["recording.stopping","recording.stop"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordListening: #"{"category":"recording","required":["recording.listening","recording.stop"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordCatchingUp: #"{"category":"recording","required":["recording.backlog","recording.stop"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordMicrophoneDenied: #"{"category":"recording","required":["recording.failure","recording.retry"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordCaptureFailure: #"{"category":"recording","required":["recording.failure","recording.retry"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordStorageFull: #"{"category":"recording","required":["recording.failure","recording.retry"],"actions":[],"anchor":"","presentation":"screen","host":"record","summaryModels":false}"#
        case .recordPermissions: #"{"category":"permissions","required":["recording.permissions.microphone","recording.permissions.allowMicrophone","system.done"],"actions":["recording.permissions"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false,"expectedText":{"recording.permissions.microphone":"Not requested"}}"#
        case .recordPermissionsDenied: #"{"category":"permissions","required":["recording.permissions.microphone","recording.permissions.openSettings","system.done"],"actions":["recording.permissions"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false,"expectedText":{"recording.permissions.microphone":"Denied"}}"#
        case .recordPermissionsAllowed: #"{"category":"permissions","required":["recording.permissions.microphone","recording.permissions.liveActivities","system.done"],"actions":["recording.permissions"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false,"expectedText":{"recording.permissions.microphone":"Allowed"}}"#
        case .recordActivitiesDisabled: #"{"category":"permissions","required":["recording.permissions.liveActivities","recording.permissions.openSettings","system.done"],"actions":["recording.permissions"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false,"expectedText":{"recording.permissions.liveActivities":"Disabled"}}"#
        case .recordPermissionPrompt: #"{"category":"permissions","required":["system.microphonePrompt"],"actions":["recording.permissions","recording.permissions.allowMicrophone"],"anchor":"","presentation":"systemPermission","host":"record","summaryModels":false}"#
        case .recordPrivacy: #"{"category":"permissions","required":["recording.privacy.overview","system.done"],"actions":["recording.privacy"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false}"#
        case .recordPrivacyDetails: #"{"category":"permissions","required":["recording.microphoneExplanation","recording.liveActivityExplanation","system.done"],"actions":["recording.privacy"],"anchor":"","presentation":"sheet","host":"record","summaryModels":false}"#
        case .meetingsNoResults: #"{"category":"library","required":["meeting.history.empty"],"actions":[],"anchor":"","presentation":"screen","host":"history","summaryModels":false,"expectedText":{"meeting.history.empty":"No matching meetings"}}"#
        case .meetingsBackupPreparing: #"{"category":"library","required":["meeting.history.backup.progress","system.done"],"actions":[],"anchor":"","presentation":"sheet","host":"history","summaryModels":false}"#
        case .meetingsBackupFailure: #"{"category":"library","required":["meeting.history.backup.error","meeting.history.backup.retry","system.done"],"actions":[],"anchor":"","presentation":"sheet","host":"history","summaryModels":false}"#
        case .meetingsRestoreConfirmation: #"{"category":"library","required":["meeting.history.backup.restore.confirm","system.cancel"],"actions":[],"anchor":"","presentation":"confirmation","host":"history","summaryModels":false,"alertTitle":"Restore this backup?"}"#
        case .meetingsRestoreFailure: #"{"category":"library","required":["meeting.history.message"],"actions":[],"anchor":"","presentation":"screen","host":"history","summaryModels":false}"#
        case .meetingsDelete: #"{"category":"library","required":["meeting.history.delete.confirm","system.cancel"],"actions":["@historyDelete"],"anchor":"","presentation":"confirmation","host":"history","summaryModels":false,"alertTitle":"Delete this meeting?"}"#
        case .meetingsReport: #"{"category":"library","required":["meeting.history.report.description","meeting.history.report.prepare"],"actions":["meeting.history.actions","meeting.history.report.prepare"],"anchor":"","presentation":"screen","host":"history","summaryModels":false}"#
        case .meetingActions: #"{"category":"library","required":["meeting.rename","meeting.delete"],"actions":["meeting.actions"],"anchor":"","presentation":"menu","host":"meeting","summaryModels":false}"#
        case .meetingRename: #"{"category":"library","required":["meeting.rename.title","meeting.rename.save"],"actions":["meeting.actions","meeting.rename"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false,"keyboard":true}"#
        case .meetingNotesEmpty: #"{"category":"notes","required":["meeting.notes.content","meeting.notes.edit"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false,"expectedText":{"meeting.notes.content":"Your thoughts, alongside the conversation"}}"#
        case .meetingNotesEditor: #"{"category":"notes","required":["meeting.notes.editor","meeting.notes.done"],"actions":["meeting.notes.edit"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingNotesSaveFailure: #"{"category":"notes","required":["meeting.notes.error","meeting.notes.copy"],"actions":["meeting.notes.edit"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingSummaryEditor: #"{"category":"summary","required":["meeting.generatedSummary.editor","meeting.summary.save"],"actions":["meeting.summary.edit"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingSummaryDetails: #"{"category":"summary","required":["meeting.summary.details.version","system.done"],"actions":["meeting.summary.details"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingSummarySources: #"{"category":"summary","required":["meeting.citation.20000000-0000-0000-0000-000000000002"],"actions":["prefix:meeting.sources."],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummaryDelete: #"{"category":"summary","required":["meeting.summary.delete.confirm","system.cancel"],"actions":["meeting.summary.options","meeting.summary.delete"],"anchor":"","presentation":"confirmation","host":"meeting","summaryModels":false,"alertTitle":"Delete summary?"}"#
        case .meetingSummaryGenerating: #"{"category":"summary","required":["meeting.intelligence.phase","meeting.intelligence.progress","meeting.intelligence.cancel"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummaryCancelling: #"{"category":"summary","required":["meeting.intelligence.phase","meeting.intelligence.progress"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummaryFailure: #"{"category":"summary","required":["meeting.intelligence.error"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingSummaryConflict: #"{"category":"summary","required":["meeting.summary.conflict.copy","meeting.summary.conflict.reopen"],"actions":["meeting.summary.edit"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingSummaryReplace: #"{"category":"summary","required":["meeting.summary.conflict.confirm","system.cancel"],"actions":["meeting.summary.edit","meeting.summary.conflict.reopen"],"anchor":"","presentation":"confirmation","host":"meeting","summaryModels":false,"alertTitle":"Replace your draft?"}"#
        case .meetingQuestionsEmpty: #"{"category":"questions","required":["meeting.qa.empty","meeting.qa.question"],"actions":[],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingQuestionComposer: #"{"category":"questions","required":["meeting.qa.question","meeting.qa.ask"],"actions":["@composeQuestion"],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false,"keyboard":true}"#
        case .meetingAnswerEditor: #"{"category":"questions","required":["meeting.qa.answer.editor.30000000-0000-0000-0000-000000000002","meeting.qa.answer.save.30000000-0000-0000-0000-000000000002"],"actions":["meeting.qa.answer.edit.30000000-0000-0000-0000-000000000002"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingAnswerSources: #"{"category":"questions","required":["meeting.citation.20000000-0000-0000-0000-000000000002"],"actions":["prefix:meeting.sources."],"anchor":"","presentation":"screen","host":"meeting","summaryModels":false}"#
        case .meetingAnswerConflict: #"{"category":"questions","required":["meeting.answer.conflict.copy","meeting.qa.answer.reopen.30000000-0000-0000-0000-000000000002"],"actions":["meeting.qa.answer.edit.30000000-0000-0000-0000-000000000002"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingAnswerReplace: #"{"category":"questions","required":["meeting.answer.conflict.confirm","system.cancel"],"actions":["meeting.qa.answer.edit.30000000-0000-0000-0000-000000000002","meeting.qa.answer.reopen.30000000-0000-0000-0000-000000000002"],"anchor":"","presentation":"confirmation","host":"meeting","summaryModels":false,"alertTitle":"Replace your draft?"}"#
        case .meetingExportMarkdown: #"{"category":"sharing","required":["meeting.export.format","meeting.export.markdown","system.done"],"actions":["@markdown"],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .meetingExportUnsaved: #"{"category":"sharing","required":["meeting.intelligence.share","meeting.export.pendingEdits","system.done"],"actions":[],"anchor":"","presentation":"sheet","host":"meeting","summaryModels":false}"#
        case .modelsSpeechVariants: #"{"category":"models","required":["prefix:models.title.","buttonPrefix:models.download.","textPrefix:models.download.label.","prefix:models.open."],"actions":[],"anchor":"models.variants.capture","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsSummaryVariants: #"{"category":"models","required":["prefix:models.title.","buttonPrefix:models.download.","textPrefix:models.download.label.","prefix:models.open."],"actions":[],"anchor":"models.variants.capture","presentation":"screen","host":"settings","summaryModels":true}"#
        case .modelsSummaryDetails: #"{"category":"models","required":["models.details.title","models.repository.title"],"actions":[],"anchor":"models.repository","presentation":"screen","host":"settings","summaryModels":true}"#
        case .modelsSummaryContext: #"{"category":"models","required":["models.details.context","models.details.output"],"actions":[],"anchor":"models.context","presentation":"screen","host":"settings","summaryModels":true}"#
        case .modelsFiles: #"{"category":"parakeet","required":["models.repository.revision","models.source.firstFile"],"actions":[],"anchor":"models.source","presentation":"screen","host":"settings","summaryModels":false}"#
        case .modelsTransferDetails: #"{"category":"downloads","required":["models.download.file","models.download.filename","models.download.speed"],"actions":["models.download.details"],"anchor":"","presentation":"screen","host":"model","summaryModels":true}"#
        case .modelsPaused: #"{"category":"downloads","required":["models.download.stage","models.download.resume"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Download paused"}}"#
        case .modelsFailed: #"{"category":"downloads","required":["models.download.stage","models.download.resume","models.error"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Download interrupted"}}"#
        case .modelsInstalling: #"{"category":"downloads","required":["models.download.stage","models.download.progress"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Installing"}}"#
        case .modelsCompleted: #"{"category":"downloads","required":["models.download.stage","models.equip.ui-model-alpha"],"actions":[],"anchor":"","presentation":"screen","host":"model","summaryModels":true,"expectedText":{"models.download.stage":"Ready to use"}}"#
        case .modelsSelected: #"{"category":"installed-models","required":["models.status.ui-model-alpha","models.equip.ui-model-alpha"],"actions":[],"anchor":"ui-model-alpha","presentation":"screen","host":"model","summaryModels":true}"#
        case .modelsStorageRequired: #"{"category":"models","required":["models.storage.required"],"actions":[],"anchor":"models.download","presentation":"screen","host":"settings","summaryModels":false}"#
        case .settingsHome: #"{"category":"settings","required":["settings.models.speech","settings.models.summary","settings.recordingPermissions"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .settingsPrivacy: #"{"category":"settings","required":["recording.privacy.overview"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .settingsPermissions: #"{"category":"settings","required":["recording.permissions.microphone","recording.permissions.allowMicrophone"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false,"expectedText":{"recording.permissions.microphone":"Not requested"}}"#
        case .settingsStorageFailure: #"{"category":"settings","required":["settings.storageAudit.error","settings.storageAudit.prepare"],"actions":[],"anchor":"","presentation":"screen","host":"settings","summaryModels":false}"#
        case .activityRecording: #"{"category":"live-activity","required":["recording.activity.status","recording.activity.elapsed","recording.activity.stop"],"actions":[],"anchor":"","presentation":"hostedActivity","host":"activity","summaryModels":false,"expectedText":{"recording.activity.status":"Recording"}}"#
        case .activityFinished: #"{"category":"live-activity","required":["recording.activity.status","recording.activity.elapsed","recording.activity.stop"],"actions":[],"anchor":"","presentation":"hostedActivity","host":"activity","summaryModels":false,"expectedText":{"recording.activity.status":"Recording saved"}}"#
        case .activityInterrupted: #"{"category":"live-activity","required":["recording.activity.status","recording.activity.elapsed","recording.activity.stop"],"actions":[],"anchor":"","presentation":"hostedActivity","host":"activity","summaryModels":false,"expectedText":{"recording.activity.status":"Recording interrupted"}}"#
        case .meetingsLoading: #"{"category":"library","required":["meeting.history.loading"],"host":"history","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingsFailure: #"{"category":"library","required":["meeting.history.error"],"host":"history","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingsRestoring: #"{"category":"library","required":["library.restoring.progress"],"host":"history","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingLoading: #"{"category":"library","required":["meeting.detail.loading"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingTranscriptNoResults: #"{"category":"transcript","required":["meeting.transcript.search","meeting.transcript.noResults"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false,"expectedText":{"meeting.transcript.noResults":"No matching words"}}"#
        case .meetingTranscriptRecovering: #"{"category":"transcript","required":["meeting.transcript.recovering"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingSummaryStructured: #"{"category":"summary","required":["meeting.generatedSummary.sections"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingSummaryEdited: #"{"category":"summary","required":["meeting.generatedSummary.content","meeting.summary.edit"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingSummaryPaused: #"{"category":"summary","required":["meeting.intelligence.message","meeting.generatedSummary.generate"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingAnswerGenerating: #"{"category":"questions","required":["meeting.intelligence.phase","meeting.intelligence.progress","meeting.qa.question"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingAnswerFailure: #"{"category":"questions","required":["meeting.intelligence.error","meeting.qa.question"],"host":"meeting","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .meetingExportFailure: #"{"category":"sharing","required":["meeting.export.unavailable","system.done"],"host":"meeting","presentation":"sheet","actions":[],"anchor":"","summaryModels":false}"#
        case .settingsStoragePreparing: #"{"category":"settings","required":["settings.storageAudit.progress"],"host":"settings","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .modelsPreparing: #"{"category":"downloads","required":["models.download.preparing"],"host":"model","presentation":"screen","actions":[],"anchor":"","summaryModels":true}"#
        case .modelsNoTransfer: #"{"category":"downloads","required":["models.transfer.empty"],"host":"model","presentation":"screen","actions":[],"anchor":"","summaryModels":true}"#
        case .modelsFailure: #"{"category":"models","required":["models.error"],"host":"settings","presentation":"screen","actions":[],"anchor":"","summaryModels":false}"#
        case .launchScreen: #"{"category":"launch","required":["text:LocalMinutes","text:Your meetings. Your device."],"host":"launch","presentation":"hostedLaunch","actions":[],"anchor":"","summaryModels":false}"#
        case .recordModelSetup: #"{"category":"recording","required":["models.family.parakeet-v2","system.done"],"host":"record","presentation":"sheet","actions":["recording.modelRequired.choose"],"anchor":"","summaryModels":false}"#
        case .meetingModelSetup: #"{"category":"summary","required":["models.family.qwen25","system.done"],"host":"meeting","presentation":"sheet","actions":["meeting.intelligence.chooseModel"],"anchor":"","summaryModels":true}"#
        }
    }
}

struct AppScreenshotSpecification: Decodable {
    let category: String
    let required: [String]
    let actions: [String]
    let anchor: String
    let presentation: String
    let host: String
    let summaryModels: Bool
    var alertTitle: String? = nil
    var keyboard: Bool? = nil
    var expectedText: [String: String]? = nil
}
#endif
