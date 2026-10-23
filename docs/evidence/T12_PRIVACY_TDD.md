# T12 persistent-file privacy — native test-first gate

Seven native cases are activated from docs/drafts/T12Privacy/ before policy
implementation. They require actual iOS metadata on default app roots,
verified model imports, SQLite/WAL/SHM/recreation, CAF/checkpoint creation and
symlink safety. No mocked filesystem/inference and no owner meeting data.
The existing ModelStoragePolicy.protectPersistentDirectory still throws
notImplemented. Root/default constructors do not yet establish the policy.

Actual SDK RED is required before implementing protection/exclusion. Compile
failure or absent cases will not count. Hosted simulator metadata cannot prove
physical locking, encryption, backup-network behavior or signing renewal.
All owner-run physical gates remain NOT_RUN. Next: final permitted invocation
run compiles the new native tests, records exact result, then implement only
after meaningful assertion RED and preserve a checkpoint if CI budget is used.
