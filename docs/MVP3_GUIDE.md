# LocalMinutes MVP3 guide

**MVP3 delivered for iLoader.** [Run40181776855](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40181776855) passed the owner-requested functionality/reliability gate:25 focused Swift cases,46 script checks,100 app-hosted cases,10 screen tests,13 packaging cases,2 device-contract and2 fixture-boundary cases, and3 real IPA hygiene cases. No failures or mandatory skips. Windows independently verified downloaded bytes, source stamps, device bundles, dependency pins and exact bundled notices. Model quality is owner-manual; physical acceptance remains **NOT_RUN**.

| Delivery item | Value |
|---|---|
| IPA directory | `build/delivery/MVP3-Functional-40181776855` |
| IPA | `LocalMinutes-1.0-880d3dcd2e21f79e6435ec134279cad192e7435d-unsigned.ipa` |
| Source | `880d3dcd2e21f79e6435ec134279cad192e7435d` |
| SHA-256 | `b0bc6e2d618f742ab257b85bc81765b25ca34b94b3c9d09fe33656b7aea1f5c9` |
| Version / build / size | 1.0 / 4 /14,855,799 bytes |
| Provenance | `build-manifest.json`, `dependency-receipt.json` and checksums beside IPA |
| Retained copy | Owner-only unpublished draft `mvp-preview-880d3dcd2e21`; no public release |

## Updating the app

Use [the Windows installation guide](WINDOWS_INSTALL.md) to install the delivered unsigned IPA through iLoader. Install over the existing app with the same Apple Account and installed bundle identifiers; preserve the Live Activity extension. Export a backup first. Do not uninstall for the seven-day refresh or replace the app during recording.

The identifiers remain `com.niranjankaruna.localminutes` and `com.niranjankaruna.localminutes.LiveActivity`. Database schema5 is retained. An older app supporting only schema4 is not a supported downgrade. **Record** explains microphone permission and Live Activity status/Stop; **Models → About LocalMinutes** shows the installed version and build.

## Speech, summaries and questions

In Models, choose Speech or Summary, look up a Hugging Face repository, read its model card and compatibility explanation, and choose a supported variant. Download or import the verified files, then Equip. Multiple alternatives can remain installed; exactly one Speech model and one Summary model can be equipped independently. Remove deletes the selected installed model, not meetings. A model currently in use cannot be removed.

Speech engines are CPU sherpa-onnx for the reviewed streaming Zipformer set, CPU whisper.cpp for compatible Whisper GGML files, and native Core ML plus Swift TDT for the reviewed Parakeet v2 conversion. Parakeet now defaults to CPU-only; new phone performance checks are needed. Original PyTorch or NeMo files need conversion. Arbitrary ONNX or Core ML files do not establish runtime compatibility.

Summaries and questions use CPU llama.cpp with supported Phi3 or Qwen2 GGUF templates. In **Models → Summary**, paste your preferred compatible repository, choose a file, download/import it and Equip. Replace any legacy suggested repository with your own choice. Summary weights are separate downloads; Phi-3 is not required. You will assess your chosen model's output manually. Automated quality benchmarks were stopped at your request; historical results remain recorded without being relabelled as passes.

Finish recording before generating a summary or asking questions. Review generated claims and their sources. Manual notes, transcript and generated material remain separate. Unsupported output is rejected. **Play source at…** selects/highlights the linked transcript row, clears its search filter as needed and requests playback at the validated source offset. Phone behavior remains part of your walkthrough.

## Meetings and recovery

Meetings contains history, transcript search, manual notes, playback and export. History labels reflect persisted transcript/summary existence; they do not claim recognition is complete. An unavailable status means its data could not be read. Original transcript appears before generated Summary/Ask sections. Delete Meeting removes that meeting's recorded audio, transcript, generated summaries, questions and notes. Ordinary deletion is not a guarantee of forensic erasure.

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
