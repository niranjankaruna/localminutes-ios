This test audits the actual delivered unsigned IPA, without extracting or changing it.
It reuses `validateArchiveEntries` for the established app/extension path rules and
checks entry types, size bounds and CRC before reading Mach-O symbol tables.

Set `LOCALMINUTES_AUDIT_IPA`, `LOCALMINUTES_AUDIT_SOURCE_COMMIT` and
`LOCALMINUTES_AUDIT_IPA_SHA256` to the exact reviewed package/receipt values, then run:

```text
python -m unittest discover -s scripts/native-hygiene-tests -p "test_*.py" -v
```

Python standard library and Node.js are the only tools used. A missing artifact,
checksum mismatch, invalid ZIP or unsupported Mach-O is a setup failure, not a
meaningful behavioral RED. Genuine RED requires the source/receipt and retained
CPU ASR entry-point controls to pass while the actual defined-symbol gate fails.

The gate excludes STAB/debug records and undefined imports. It matches anchored
eSpeak/Piper implementation namespaces, not arbitrary strings or case-folded
`Speaker` class names. Stripping symbol names is not an acceptable repair.
Absence of these names alone is not a complete license or reachability audit;
retain source/build/archive inventory and real CPU Zipformer inference evidence.
No project-license change is authorized by this check.
