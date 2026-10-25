# MVP4: phone acceptance

MVP4 build6 development is delivered; phone acceptance requires actual observations. No phone
gate is passed by hosted tests. Model choice and output-quality assessment are
owner-manual, as requested on25October2026.

Use the IPA in `build/delivery/MVP4-Final-40190643613`, version1.0/build6,
source `36bf6f4c8726fbc5d2efbfa4f740ef4031457233`.
SHA256: `08c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0`.
See [MVP4 setup](MVP4_GUIDE.md) and [Windows installation/renewal](WINDOWS_INSTALL.md).

- [ ] Install over the existing app through iLoader with the same account and
  installed bundle-ID settings; preserve the Live Activity extension. Record
  actual phone model, iOS, iLoader version and installed app/extension IDs.
- [ ] In Models, download/import and Equip your chosen supported Speech and
  Summary models separately. Record exact repository, file, revision and hashes.
  Check switching between installed alternatives, removal and remembered choices
  after reopening the app. Phi-3 is not a required download.
- [ ] Make two disposable short meetings. Check live text, Stop, saved playback,
  notes, history/search, summary/Q&A controls and source navigation. Confirm
  meeting isolation; deleting one removes its audio/transcript/generated content
  while the other remains. Assess model output manually.
- [ ] Edit a saved answer, save, reopen the meeting and relaunch. Confirm the edit persists while original transcript/manual notes remain intact. Check older history pages and Load more matches when applicable.
- [ ] With recording/playback/processing stopped, use Models → Prepare storage check. Keep the report and compare actual protection/backup metadata before and after renewal; unknown/incomplete facts remain unverified.
- [ ] Repeat a short recording and local summary/question with network disabled
  after setup. Installation, renewal and model downloads require connectivity.
- [ ] Verify the Live Activity displays status and its Stop control saves the
  meeting. Test Action Button warm/unlocked, locked continuation and locked cold
  start separately. Record any unlock requirement; do not call it a cold-start pass.
- [ ] Perform **two separate125-minute recordings**, each including at least120
  continuous locked minutes. Use a separate [device report](templates/DEVICE_TEST_REPORT.md)
  for each pass and independent start/lock/stop/unlock times. Export the sampled
  recording report; check progress during the locked interval, gaps, backlog,
  latency, memory, thermal state, battery and saved audio. A timer or text visible
  only after unlocking does not prove live locked recognition.
- [ ] Export a complete library backup before renewal. Refresh in place with
  iLoader using the same account/IDs, without uninstalling or interrupting a
  recording. Recheck meetings, notes, audio, models, Equip choices and shortcuts.

Keep real audio, transcripts, backups, account details and raw device logs private.
Only sanitized observations and evidence hashes belong in the repository.

Current result: **all device checks NOT_RUN**. The owner performs endurance tests.
Owner-reported device: iPhone17Pro, iOS27.0.1 (not independently observed).
Required next input: installed build6 and the short Live Activity/Stop observation.
After reports arrive, compare them with the exact artifact/model pins and audit
the remaining gates. Set `VERIFIED_COMPLETE` only after required evidence exists;
record failures or unlock-required behavior explicitly.
