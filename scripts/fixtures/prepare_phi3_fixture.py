#!/usr/bin/env python3
"""Prepare the pinned Phi-3 model used by native integration tests."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import urllib.request

import prepare_native_summary as native

REVISION = "a64113399c2f6b8ad3e11c394733a2ddadaa7f33"
NAME = "Phi-3-mini-4k-instruct-q4.gguf"
SIZE = 2393231072
SHA = "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef"
BASE = "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/" + REVISION + "/"


def main():
    workspace = Path.cwd().resolve()
    root = workspace / ".agent-local" / "phi3-fixtures"
    if root.is_symlink() or (workspace / ".agent-local").is_symlink() or not native.inside(root, workspace):
        raise ValueError("Unsafe fixture root")
    root.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(root).free < 3_000_000_000:
        raise ValueError("Insufficient fixture disk space")
    native.HOSTS.update({"cas-bridge.xethub.hf.co", "cdn-lfs.huggingface.co", "cdn-lfs-us-1.hf.co"})
    model = root / NAME
    # The shared helper rehashes every cached model and checks exact bytes/SHA
    # before reuse; incomplete transfers never become the selected artifact.
    native.download(BASE + NAME, model, SIZE, SHA)

    license_url = BASE + "LICENSE"
    native.approved(license_url)
    opener = urllib.request.build_opener(native.RedirectPolicy())
    with opener.open(urllib.request.Request(license_url, headers={"User-Agent": "LocalMinutes-fixture"}),
                     timeout=45) as response:
        native.approved(response.url)
        if response.status != 200:
            raise ValueError("Unexpected license distribution status")
        license_bytes = response.read(16_385)
    if not license_bytes or len(license_bytes) > 16_384:
        raise ValueError("Unexpected license size")
    license_text = license_bytes.decode("utf-8")
    if "MIT License" not in license_text or "Permission is hereby granted" not in license_text:
        raise ValueError("Pinned license is not the reviewed MIT text")
    license_path = root / "LICENSE-PHI.txt"
    partial = root / "LICENSE-PHI.txt.part"
    if license_path.is_symlink() or partial.is_symlink():
        raise ValueError("Unsafe fixture license destination")
    try:
        partial.write_bytes(license_bytes)
        os.replace(partial, license_path)
    finally:
        partial.unlink(missing_ok=True)
    print(json.dumps({"testFixture": True, "revision": REVISION, "modelBytesVerified": SIZE,
                      "modelSHA256": SHA, "modelPath": str(model), "license": "MIT",
                      "licenseBytes": len(license_bytes),
                      "licenseSHA256Actual": hashlib.sha256(license_bytes).hexdigest()}, indent=2))
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
            environment.write("LOCALMINUTES_PHI_MODEL_PATH=" + str(model) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Fixture preparation failed: " + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
