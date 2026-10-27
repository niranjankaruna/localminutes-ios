import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
import LocalMinutesSummary
import LocalMinutesQuestionAnswering
#endif

/// Fixed, actionable messages only. Never display arbitrary localizedDescription:
/// native and storage errors may include private transcript text or file paths.
public enum IntelligenceFailureMessage {
    public static func message(for error: Error) -> String {
        switch error {
        case IntelligenceSessionError.transcriptMissing:
            return "This meeting has no finalized transcript. Finish transcription before creating a summary."
        case IntelligenceSessionError.invalidModel, LocalSummaryRuntimeError.invalidModel:
            return "The selected model could not be loaded. Remove and download it again, or equip another model."
        case LocalSummaryRuntimeError.modelUnavailable:
            return "The selected model is not installed. Download and equip a summary model in Settings."
        case LocalSummaryRuntimeError.contextUnavailable:
            return "There is not enough available memory to load this model. Close other apps or equip a smaller summary model."
        case LocalSummaryRuntimeError.contextExceeded, AppleFoundationRuntimeError.contextExceeded,
             SummaryChunkPlannerError.oversizedSegment, MeetingQuestionError.evidenceExceedsBudget:
            return "A transcript section or the meeting notes exceeds this model's input limit. Shorten the notes or try another summary model."
        case LocalSummaryRuntimeError.outputLimitExceeded:
            return "The model could not finish its response within the output limit. Try again or equip another summary model."
        case AppleFoundationRuntimeError.unavailable(let availability):
            return availability.explanation
        case AppleFoundationRuntimeError.rateLimited:
            return "Apple Intelligence is temporarily busy. Wait a moment, then try again."
        case AppleFoundationRuntimeError.busy:
            return "Apple Intelligence is already generating a response. Wait for it to finish, then try again."
        case AppleFoundationRuntimeError.refused:
            return "Apple Intelligence declined to process this content. You can try an installed summary model instead."
        case AppleFoundationRuntimeError.unsupportedLanguage:
            return "Apple Intelligence does not support this content's language or locale. Try an installed summary model."
        case AppleFoundationRuntimeError.unsupportedSchema, AppleFoundationRuntimeError.invalidRequest,
             is StructuredJSONSchemaError:
            return "The model could not use the requested response format. Try another summary model and check for an app update."
        case GroundedSummaryError.invalidSource, SummaryChunkPlannerError.invalidSource,
             SummaryChunkPlannerError.duplicateSegmentID:
            return "The saved transcript has invalid source ranges. Transcribe the meeting again before summarizing it."
        case is GroundedSummaryError, MeetingQuestionError.invalidJSON, MeetingQuestionError.unsupportedEvidence:
            return "The model's response could not be verified against this transcript. Nothing was saved. Try again or equip another summary model."
        case LocalSummaryRuntimeError.generationFailed, AppleFoundationRuntimeError.generationFailed:
            return "The model could not complete a valid response. Try again or equip another summary model."
        default:
            return "Generation could not be completed or saved. Try again. If it continues, reopen LocalMinutes and check the selected summary model."
        }
    }
}
