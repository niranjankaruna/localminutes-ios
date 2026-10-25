# Local summaries and questions

Current build 6 includes local summaries, selected-meeting questions, source
navigation, editable generated summaries, and saved-answer editing. Hosted
functional evidence is in [VERIFICATION.md](VERIFICATION.md). Output quality is
assessed manually by the owner; physical-phone operation remains unverified.

1. Install and **Equip** a compatible [summary model](MODELS.md). The owner chooses
   the model; Phi-3 is not required. Keep model weights separate from the IPA.
2. Stop recording, open a saved meeting, and choose **Generate summary**. Keep the
   app in the foreground. Summary inference is admitted separately from live capture.
3. Review source references and use **Play source** to inspect the matching
   transcript/audio position. Edit the generated summary separately from original
   notes. A save conflict preserves the draft instead of overwriting newer content.
4. Enter a question under **Ask this meeting**, then choose **Ask**. Retrieval and
   answers are restricted to that meeting. Insufficient evidence is an explicit
   outcome; generated results must pass source/schema checks before saving.
5. Edit a saved answer and tap **Save answer**. Leaving the meeting flushes edits;
   a revision conflict preserves the draft. Copy it before choosing **Reopen saved
   answer**. Edits do not change the original transcript, notes, or source evidence.
6. **Cancel**, leaving the meeting, backgrounding, and memory warnings request
   cancellation and model cleanup. Capture has priority. Durable summary
   checkpoints support resume; bounded context and item limits may still reject
   a long or unusually dense meeting without publishing a partial result.
7. **Share generated notes and answers** exports the selected generated content,
   questions, source quotes, and model/prompt provenance to your chosen destination.

Exact quotes and valid JSON do not guarantee factual correctness. Review output
against its sources and chosen model. Historical model failures and their tests
remain available in [evidence](evidence/); they have not been relabeled as passes.
See [meeting backup and recovery](LIBRARY.md) before updates or renewal.
