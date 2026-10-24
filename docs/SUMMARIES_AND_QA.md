# Local summaries and questions

**Current status: screens and model wiring compile, but the pinned model has not passed the summary/Q&A quality gate. Incorrect or unsupported output is rejected, and some requests return an error. This is a feature preview.**

This feature preview adds Summary and Ask sections to a saved meeting. It requires the separate local summary-model download.

1. Install the new unsigned IPA over the existing app using the same Sideloadly Apple Account and bundle-ID settings. Avoid uninstalling to preserve the existing container; actual renewal/data preservation remains unverified.
2. Open **Models → Download summary model**. The pinned Qwen download is about1.12GB. Wait for **Summary model verified**. Model setup needs internet; generation uses the installed model locally.
3. Stop recording, open **Meetings**, and select the meeting. Tap **Generate summary**. Keep the app in the foreground until generation finishes.
4. Edit the generated summary separately from your original notes. Changes autosave; **Save summary** retries a failed save. A revision-conflict message protects a newer saved copy from being overwritten.
5. Enter a question under **Ask this meeting**, then tap **Ask**. Saved answers and supporting original quotes appear only in the selected meeting. Use **Play source** to open the cited audio position.
6. **Cancel**, leaving the meeting, or backgrounding the app cancels that request and releases its local model. Starting a recording gives capture priority and waits for model cleanup. Original notes/transcripts remain intact.
7. Use **Share generated notes and answers** to export the selected generated copy, questions, source quotes and model/prompt provenance. Sharing sends that text to the destination you choose.

Generated results must pass schema and selected-source quote checks before saving. Review them against their sources; an exact quote is not a general guarantee of factual entailment. Unsupported generation shows a recoverable error. Original manual notes are preserved and supplied as context, while citations currently refer to finalized transcript sources.

The current implementation has explicit context, atomic-segment, map and total-item limits. A very long or unusually dense meeting may exceed them and fail without publishing a partial summary. Long-meeting summarization, notes-only citations, checkpoint resume, representative model quality and physical-phone behavior remain pending baseline work.

The build/check results and exact downloadable IPA are recorded in the feature delivery handoff. Existing MVP files remain available separately.
