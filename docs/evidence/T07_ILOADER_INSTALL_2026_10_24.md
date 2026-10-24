# T07 iLoader installation and reference update

Checkpoint: 2026-10-24T15:31:15.814076Z. Owner instruction: iLoader installation succeeded;
replace the project's installer references with iLoader.

The owner reports successful main-app installation through iLoader. This
resolves the previous installer authentication blocker for the installation
path. The exact installed IPA/source, phone model/iOS, tool version and signing
details were not supplied. No automatic device inspection was performed.

T07 is IN_PROGRESS: the embedded Live Activity extension, status/Stop controls,
Action Button warm and locked cold start, live transcription while locked,
offline inference, two 125-minute runs, file protection and in-place renewal
remain unverified. Installation alone does not pass those acceptance criteria.

T07.1, selecting iLoader and updating installation references, is complete.
Project instructions, configuration, app renewal copy, Markdown and Word brief,
source register, Windows guides and local delivery-guide copies now use iLoader.
The installed app's renewal copy changes only after a future build/install;
the delivered IPA files are unchanged. No rebuild or CI was dispatched.

[iLoader's official site](https://iloader.app/) documents Windows and custom IPA
support, with iTunes as a Windows prerequisite. Only that site and the
[official repository](https://github.com/nab138/iloader) are used for downloads.
[Release v2.4.0](https://github.com/nab138/iloader/releases/tag/v2.4.0) was the
version observed upstream; it is not a claim about the owner's installed version.

Earlier notes recorded error -80046 from the previous installer and researched
alternatives without claiming success. They are superseded by the owner's
installation report. The original chronological record is retained in Git
history; no historical failure has been relabelled as an iLoader failure.

Validation for this content change: JSON parsing, changed-file review, search
for superseded installer references and whitespace checks. No behavior tests,
native builds, real-model or physical-device tests are run by this invocation.
Latest relevant existing CI rechecked: run40105186439, source6d914fe, terminal
cancelled. Its existing model observations are unchanged and do not validate
this copy update. No new IPA or signed artifact is produced.

Final content checks passed: all three configuration/state JSON files parse;
no superseded installer names remain in the current repository text or local
delivery guides; the two delivered IPA SHA-256 values are unchanged. Word ZIP
and XML validate, all 348 paragraphs remain, five paragraphs have revised
text, and Word styles are byte-identical. The packaged renderer was attempted
but cannot render because LibreOffice is absent; Microsoft Word is also not
registered. Visual Word review remains pending and is not claimed as passed.
No commit or push is made by this invocation; unrelated concurrent workflow
and model-test edits remain outside this reference migration.

Next T07 action: record the installed IPA/source, actual phone/iOS and iLoader
version, then verify the embedded Live Activity status and Stop control with a
short recording. Use iLoader for future manual renewal with the same account
and installed bundle-ID settings; retain the existing app. Model development
remains at its independently saved pause/checkpoint.
