# T09 actual production download and inference integration

One mandatory case testActualPinnedHTTPSDownloadInstallsReopensImportsAndRecognizesUnderLease downloads all4 actual pinned speech artifacts (72,654,782bytes) using the unchanged production HTTPS transport/host policy and real installer. Independent stream hashes, license/selection metadata, lease deletion guard, Files-style import/reopen and actual native CPU recognition of the existing licensed fixture are required. No opt-in, skipped network result, URLProtocol double or mocked inference. Request20s/resource75s bounds per artifact.

Read-only actualHEADchains used huggingface.co redirects to us.aws.cdn.hf.co (ONNX) or huggingface.co (tokens), all approved; reported lengths match manifest. Fullchains stay ignored. No production allowlist change. This expands integration evidence for existing behavior; no fabricated failing test is required if it already works. Hosted compile/execution pending, never claimed as GREEN from HEAD.


## Exact-source full regression GREEN

`db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` / [run40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180) completed SUCCESS.269core/59scripts/85TSAN/5actualQwen/59native/3UI/2bundle/13archive cases all pass,0failures/skips/reported races; native/UI xcresult agrees. This supersedes earlier pending-GREEN statements for the bounded component above. It does not complete its broad parent feature or any physical gate. Source, artifact, limits and exact remaining work: [continuation08 checkpoint](CONTINUATION_08_CHECKPOINT.md).
