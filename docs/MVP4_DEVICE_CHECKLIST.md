# MVP4: phone acceptance

MVP3 is delivered; MVP4 requires observations from the actual iPhone. No phone
gate is passed by hosted tests. Model choice and output-quality assessment are
owner-manual, as requested on25October2026.

Use the IPA in `build/delivery/MVP3-Functional-40181776855`, version1.0/build4,
source `880d3dcd2e21f79e6435ec134279cad192e7435d`.
SHA256: `b0bc6e2d618f742ab257b85bc81765b25ca34b94b3c9d09fe33656b7aea1f5c9`.
See [MVP3 setup](MVP3_GUIDE.md) and [Windows installation/renewal](WINDOWS_INSTALL.md).

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
Required next input: phone/iOS facts and the short Live Activity/Stop observation.
After reports arrive, compare them with the exact artifact/model pins and audit
the remaining gates. Set `VERIFIED_COMPLETE` only after required evidence exists;
record failures or unlock-required behavior explicitly.
