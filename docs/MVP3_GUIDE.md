# LocalMinutes MVP3 guide

**Delivery pending.** This guide describes the MVP3 candidate under development. The verified downloadable build remains [MVP2](MVP2_GUIDE.md) until this page records an exact passing source, run and IPA checksum. Physical-device acceptance remains separate.

## Updating the app

Use [the Windows installation guide](WINDOWS_INSTALL.md) to install the delivered unsigned IPA through iLoader. Install over the existing app with the same Apple Account and installed bundle identifiers; preserve the Live Activity extension. Export a backup first. Do not uninstall for the seven-day refresh or replace the app during recording.

The intended identifiers remain `com.niranjankaruna.localminutes` and `com.niranjankaruna.localminutes.LiveActivity`. Database schema 5 is retained. An older app supporting only schema 4 is not a supported downgrade.

## Speech, summaries and questions

In Models, choose Speech or Summary, look up a Hugging Face repository, read its model card and compatibility explanation, and choose a supported variant. Download or import the verified files, then Equip. Multiple alternatives can remain installed; exactly one Speech model and one Summary model can be equipped independently. Remove deletes the selected installed model, not meetings. A model currently in use cannot be removed.

Speech engines are CPU sherpa-onnx for the reviewed streaming Zipformer set, CPU whisper.cpp for compatible Whisper GGML files, and native Core ML plus Swift TDT for the reviewed Parakeet v2 conversion. Original PyTorch or NeMo files need conversion. Arbitrary ONNX or Core ML files do not establish runtime compatibility. The candidate's default Parakeet compute policy and measured quality must be confirmed in its delivery evidence before release.

Summaries and questions use CPU llama.cpp with supported Phi3 or Qwen2 GGUF templates. The selected Phi candidate is `microsoft/Phi-3-mini-4k-instruct-gguf`, `Phi-3-mini-4k-instruct-q4.gguf` (about 2.39 GB). Model compatibility is separate from measured output quality. Existing Qwen quality limitations remain documented; downloading a supported file does not guarantee accurate answers.

Finish recording before generating a summary or asking questions. Review generated claims and their sources. Manual notes, transcript and generated material remain separate. Unknown information should be refused instead of invented. A source link should select its transcript row and request playback at that source offset; this binding is still awaiting MVP3 verification.

## Meetings and recovery

Meetings contains history, transcript search, manual notes, playback and export. Delete Meeting removes that meeting's recorded audio, transcript, generated summaries, questions and notes. Ordinary deletion is not a guarantee of forensic erasure.

Use explicit backup/export before important updates or renewal. Exports saved to a cloud-backed Files location can leave the phone at your direction. Diagnostics should contain technical facts rather than meeting text. An interrupted recording can offer recovery using its captured model pins; see [MVP2 recovery and backup instructions](MVP2_GUIDE.md).

## Owner checks after delivery

- Record the delivered source, installed build, phone model, iOS and iLoader version.
- Confirm a short recording produces real local text and playable saved audio.
- Confirm the embedded Live Activity displays status and its Stop control works.
- Assign the recording shortcut to the Action Button. Check locked continuation and locked cold-start separately; report any unlock requirement.
- After model installation, check recording, summaries and questions without internet.
- Perform the two 125-minute locked-screen meetings on the final candidate and export the bounded diagnostics.
- Renew in place with the same identity and verify meetings, models, settings and shortcut preservation.

None of these device-only checks is passed by a simulator build. The owner performs the endurance tests; evidence must identify the exact installed candidate.
