# Model upgrades: iPhone checks

Candidate build and exact checksum: consult `STATE.json`; a pending build is not
an installed or tested phone result. Keep the previous build and a meeting backup.
These checks supplement the [existing device checklist](MVP4_DEVICE_CHECKLIST.md).

## Models screen

- Confirm the installed version/build. Speech and Summary choices remain separate.
- Existing Parakeet v2 remains installed after updating over the app. Its row shows
  the name, total size and Equipped state. Model details expands its internal files.
- Privacy and renewal and Action Button sections are absent. This iPhone appears
  at the end. Larger accessibility text keeps Equip and Remove reachable.

## Download and resume

- Browse Parakeet TDT v3 and review its pinned source and license. Start a download;
  check percentage, total bytes, current file/count, speed and estimated time.
- Pause during a large weight file. Resume the same pack. The saved prefix is
  verified and reported; previously downloaded files are retained safely.
- Check the distinct verification and installation stages. Completion means
  installation succeeded, followed by an explicit Equip choice.
- Repeat with the owner's chosen compatible summary GGUF. Record success or the
  observed failure stage. A crash still needs its actual iOS termination reason;
  the automated transfer-memory regression alone cannot diagnose a phone crash.

## Local inference

- With models installed, enable Airplane Mode. Equip v2 and make a short meeting;
  confirm text appears before stopping. Repeat with v3. Judge model output manually.
- Reopen a saved meeting after changing the equipped model. Transcript recovery
  must use its captured original model pin or explain that its installation is
  unavailable. It must not silently substitute today's selection.
- During recording or generation, changing an equipped model must remain blocked
  until the active work and cleanup finish.

## Apple Intelligence

- Summary lists Apple Intelligence and an actual availability explanation. When
  the system model is unavailable, its Equip action is disabled.
- Once iOS reports the on-device model ready, Equip it. Reopen LocalMinutes and
  confirm the selection persists without requesting a downloaded summary file.
- After system setup is complete, test in Airplane Mode: create a summary and ask
  one supported question and one unknown question. Confirm saved evidence belongs
  to this meeting and original notes/transcript remain unchanged. Unknown owners
  and dates must remain unknown. These are phone inference checks, not simulator
  inference claims or automated model-quality benchmarks.
- Switch to an installed GGUF and back while idle. Speech selection must persist.
  Cancel a request and confirm recording becomes available after cleanup.

## Remaining release gates

The existing physical gates still apply: free signing and the embedded Live
Activity, its Stop control, Action Button warm/locked/cold-start behavior,
two 125-minute meetings with at least 120 locked minutes each, offline operation,
file protection, and in-place seven-day signing renewal with preserved storage.
Record any unlock requirement explicitly. No checkbox above passes these gates.
