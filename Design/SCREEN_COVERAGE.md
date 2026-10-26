# Screen coverage

All 41 supplied screenshot scenes have redesigned equivalents in both appearances. Additional states cover setup, progress, recovery, permission, editing, and failure flows found in the source.

- Application and system states: **116 per appearance / 232 frames**.
- Review launcher and index: **31 frames**.
- Source of truth: [navigation and meeting detail](../App/LocalMinutesHomeView.swift), [recording](../App/RecordingControlsView.swift), [summaries and questions](../App/MeetingIntelligenceView.swift), [models](../App/ModelBrowserView.swift), [scene catalog](../Shared/AppScreenshotScene.swift), and [Live Activity](../LiveActivityExtension/LocalMinutesLiveActivity.swift).

| Original screenshot scene | Redesigned frame | Light node | Dark node |
| --- | --- | --- | --- |
| record_idle | 02 · Ready to record | 8979 | 4459 |
| record_speech_model_required | 24 · Speech model required | 946 | 5348 |
| record_active | 03 · Recording | 96 | 4498 |
| record_live_transcript | 29 · Live transcript | 1106 | 5508 |
| record_live_notes | 30 · Live notes | 1146 | 5548 |
| meetings_empty | 09 · Meetings · empty | 9687 | 10101 |
| meetings_history | 01 · Meetings | 5 | 4407 |
| meetings_actions | 12 · Library actions | 490 | 4892 |
| meetings_backup_ready | 13 · Backup ready | 561 | 4963 |
| meetings_restore_picker | 16 · Restore · Files | 639 | 5041 |
| meetings_search | 10 · Meetings · search | 9721 | 10135 |
| meeting_delete_confirmation | 22 · Delete confirmation | 849 | 5251 |
| meeting_notes | 06 · Notes | 231 | 4633 |
| meeting_transcript | 05 · Transcript | 183 | 4585 |
| meeting_transcript_search | 36 · Transcript search | 1392 | 5794 |
| meeting_no_transcript | 38 · No transcript | 1491 | 5893 |
| meeting_summary | 04 · Meeting summary | 136 | 4538 |
| meeting_summary_reset_confirmation | 47 · Reset summary progress | 1925 | 6327 |
| meeting_no_summary | 42 · No summary | 9077 | 6092 |
| meeting_summary_model_required | 43 · Summary model required | 1730 | 6132 |
| meeting_questions_and_answers | 07 · Ask a meeting | 270 | 4672 |
| meeting_export | 59 · Export · text | 2591 | 6993 |
| meeting_share_sheet | 62 · System share sheet | 2745 | 7147 |
| models_speech | 65 · Speech model setup | 2883 | 7285 |
| models_summary | 66 · Summary models | 9117 | 7334 |
| models_parakeet_repository | 74 · Parakeet · overview | 9316 | 7673 |
| models_parakeet_source | 76 · Parakeet · source | 9356 | 7752 |
| models_parakeet_compatibility | 78 · Model compatibility | 3422 | 7824 |
| models_parakeet_requirements | 79 · Speech requirements | 3451 | 7853 |
| models_parakeet_download | 81 · Download or import | 3525 | 7927 |
| models_import_picker | 83 · Import model · Files | 3583 | 7985 |
| models_pack_picker | 84 · Open model pack · Files | 3617 | 8019 |
| models_model_card | 92 · Model card | 3838 | 8240 |
| models_downloading | 85 · Downloading speech model | 3651 | 8053 |
| models_verifying | 88 · Verifying model | 3731 | 8133 |
| models_installed_summary | 67 · Installed summary models | 9171 | 7388 |
| models_installed_details | 68 · Installed model details | 9225 | 7442 |
| models_remove_confirmation | 70 · Remove summary model | 9266 | 7522 |
| models_storage_check | 101 · Storage check | 4071 | 8473 |
| models_about | 105 · About & diagnostics | 9479 | 8593 |
| models_device | 104 · This iPhone | 4162 | 8564 |

## Content decisions

- Routine recording screens lose the repeated permission and Live Activity paragraphs. These are available contextually and in Privacy.
- Meeting rows keep title, date/time, duration, and a short content preview. Healthy transcript/summary status is not repeated on every row; issues remain visible.
- Meeting name editing moves to the meeting actions menu. Notes, transcript, summary, and questions become distinct views.
- Generated text is presented for reading first; editing is explicit. Citations open the source transcript and playback. Original source content remains distinct from edited generated content.
- Model revision hashes, runtime identifiers, checksums, resource estimates, and reports move into dedicated details. Compatibility does not claim that device performance has been verified.
- “Equip” becomes “Use for recording” or “Use for summaries.” Installation and selection remain separate steps.
- Destructive confirmations preserve the actual source semantics: resetting only discards unfinished summary progress; restoring retains the previous library; deleting a meeting removes its data.
- Progress percentages appear only where the source exposes measurable model transfer progress. Other operations use an indeterminate indicator.

## Prototype boundaries

The prototype uses illustrative meeting content, model examples, and resource measurements. Keyboard entry, microphone permission, file pickers, sharing, model downloads, recording, inference, and storage checks are simulated. No real audio is captured, no model is downloaded, and no meeting data is changed by clicking this design.

