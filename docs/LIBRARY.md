# Meetings, backup, and recovery

## History, notes, and playback

Open **Meetings** to browse saved recordings. **Load more meetings** reaches older
pages; title search covers the library. Transcript search offers **Load more
matches** beyond its first page. Select a meeting for its transcript, original
manual notes, audio, summaries, and saved answers. Source links navigate to their
matching audio position. Generated text is kept separate from original content.

Use the meeting's text/Markdown share actions for readable exports. Generated
notes and answers have their own export including questions and source references.
Sharing sends that content to the destination you select; text exports are not a
complete database/audio backup. Confirm deletion to remove the selected meeting
and its active-library artifacts.

## Backup and restore

Finish recording, playback, processing, and edits first. Use **Meetings → Library
actions → Create library backup** and retain the complete exported folder.
The backup includes the library snapshot and audio; model installations remain
separate. Keep it private and retain its folder structure.

Choose **Restore library backup…**, select the complete folder, and confirm
replacement. The restored library becomes active; the previous library is
retained, and installed models remain separate. Do not overwrite a live database
or combine backup folders manually.

Exported backups, retained previous libraries, and shares are independent copies.
Deleting a meeting from the active library does not erase those copies. Manage
them separately when removing all copies. Current database schema is 5; older
schema-4 apps refuse it, so installing an older IPA is not a downgrade procedure.

## Interrupted recordings and diagnostics

Startup reconciles durable audio and transcript checkpoints. Recovery cannot
recreate samples never written. A recovered transcript does not prove live
transcription continued while the phone was locked. Keep interrupted/gap status
visible when reviewing the recovered meeting.

Use **Library actions → Prepare recording report**, then **Share sampled recording
report**, for bounded counters and environment measurements. The report excludes
meeting text/audio and device-route names; unavailable facts remain unknown.
Use **Models → Prepare storage check → Share storage check** when work has stopped
to export observed protection/backup flags and counts. Neither report alone
establishes locked access or two-hour endurance.

Before seven-day renewal, export a backup and follow [Windows renewal](WINDOWS_INSTALL.md)
using the same account and installed app/extension identifiers. Preservation still
requires actual phone evidence in the [device checklist](MVP4_DEVICE_CHECKLIST.md).
