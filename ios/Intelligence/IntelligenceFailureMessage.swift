import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
import LocalMinutesPersistence
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
        case LocalSummaryRuntimeError.contextExceeded, NarrativeSummaryError.contextExceeded:
            return "The full transcript and expected summary do not fit the selected model's context window. Choose a summary model with a larger context window or shorten the meeting notes. Nothing was generated or saved."
        case MeetingQuestionError.evidenceExceedsBudget:
            return "The question and its transcript evidence exceed this model's input limit. Shorten the question or try another model."
        case LocalSummaryRuntimeError.outputLimitExceeded:
            return "The model could not finish a complete response within its output limit. Your transcript is unchanged. Try again or equip another summary model."
        case SummaryCheckpointError.invalidInput:
            return "The app could not save summary progress because its checkpoint format was rejected. Your transcript is unchanged. Update the app and retry."
        case SummaryCheckpointError.corruptCheckpoint, SummaryCheckpointError.conflictingMap,
             SummaryCheckpointError.nonContiguousMap:
            return "Saved summary progress could not be read safely. Choose Start from beginning to create fresh progress. Your transcript and saved summaries are unchanged."
        case SummaryCheckpointError.limitExceeded:
            return "The saved summary progress exceeded its storage limit. Your transcript and saved summaries are unchanged."
        case is StructuredJSONSchemaError:
            return "The model could not use the requested response format. Try another summary model and check for an app update."
        case GroundedSummaryError.invalidSource:
            return "The saved transcript has invalid source ranges. Transcribe the meeting again before summarizing it."
        case NarrativeSummaryError.invalidResponse:
            return "The model did not return a valid summary. Nothing was saved. Try again or equip another summary model."
        case is GroundedSummaryError, NarrativeSummaryError.unsupportedEvidence, NarrativeSummaryError.reviewRejected,
             MeetingQuestionError.invalidJSON, MeetingQuestionError.unsupportedEvidence:
            return "The model's response could not be verified against this transcript. Nothing was saved. Try again or equip another summary model."
        case LocalSummaryRuntimeError.generationFailed:
            return "The model could not complete a valid response. Try again or equip another summary model."
        case NarrativeSummaryError.limitExceeded:
            return "This meeting exceeded the summary processing limit. Try a model with more capacity. Your transcript and saved progress are unchanged."
        default:
            return "Generation could not be completed or saved. Try again. If it continues, reopen LocalMinutes and check the selected summary model."
        }
    }

    /// A stable, copyable diagnostic reference with no transcript or file paths.
    public static func code(for error: Error) -> String {
        switch error {
        case SummaryCheckpointError.invalidInput: return "LM-CHECKPOINT-FORMAT"
        case SummaryCheckpointError.corruptCheckpoint: return "LM-CHECKPOINT-CORRUPT"
        case SummaryCheckpointError.conflictingMap, SummaryCheckpointError.nonContiguousMap: return "LM-CHECKPOINT-SEQUENCE"
        case SummaryCheckpointError.limitExceeded: return "LM-CHECKPOINT-LIMIT"
        case is StructuredJSONSchemaError: return "LM-RESPONSE-FORMAT"
        case LocalSummaryRuntimeError.contextUnavailable: return "LM-MODEL-MEMORY"
        case LocalSummaryRuntimeError.contextExceeded, NarrativeSummaryError.contextExceeded: return "LM-INPUT-LIMIT"
        case LocalSummaryRuntimeError.outputLimitExceeded: return "LM-OUTPUT-LIMIT"
        case NarrativeSummaryError.invalidResponse: return "LM-INVALID-RESPONSE"
        case NarrativeSummaryError.unsupportedEvidence, NarrativeSummaryError.reviewRejected: return "LM-SOURCE-CHECK"
        case LocalSummaryRuntimeError.generationFailed: return "LM-GENERATION"
        default: return "LM-SUMMARY-FAILED"
        }
    }
}
