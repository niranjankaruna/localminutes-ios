"""Test setup only: exact public model + one CC-BY speech fixture, never inference.

Run from repository root. All downloaded bytes remain in ignored .agent-local.
No archive paths are extracted, no executable is downloaded, no voices installed.
Missing downloads or integrity mismatches fail setup.
"""
from pathlib import Path
import hashlib
import json
import tarfile
import time
import urllib.request

REVISION = "672fbf1b30579d6585301139bb363f42a0ad4a24"
MODEL_URL = "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/" + REVISION
ARTIFACTS = [
    ("encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 71083163,
     "563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1"),
    ("decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 1307236,
     "98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02"),
    ("joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 259335,
     "d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297"),
    ("tokens.txt", 5048,
     "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb"),
]
ARCHIVE_URL = "https://www.openslr.org/resources/12/test-clean.tar.gz"
UTTERANCE = "6930-75918-0000"
MEMBER = "LibriSpeech/test-clean/6930/75918/" + UTTERANCE + ".flac"
TRANSCRIPT_MEMBER = "LibriSpeech/test-clean/6930/75918/6930-75918.trans.txt"
REFERENCE = "CONCORD RETURNED TO ITS PLACE AMIDST THE TENTS"
FLAC_SIZE = 74138
FLAC_SHA256 = "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def valid(path, size, digest):
    return path.is_file() and not path.is_symlink() and path.stat().st_size == size and sha256(path) == digest


class BoundedPrefix:
    def __init__(self, response):
        self.response = response
        self.total = 0
        self.deadline = time.monotonic() + 120

    def read(self, size=-1):
        if size < 0 or self.total + size > 32 * 1024 * 1024 or time.monotonic() > self.deadline:
            raise RuntimeError("Official archive prefix exceeded32MiB/120s fixture bound")
        block = self.response.read(size)
        self.total += len(block)
        return block


def main():
    workspace = Path.cwd().resolve()
    if not (workspace / "project.yml").is_file() or not (workspace / "Package.swift").is_file():
        raise RuntimeError("Run fixture preparation from the LocalMinutes repository root")
    output = workspace / ".agent-local" / "asr-evaluation" / "native-fixtures"
    model = output / "model"
    for directory in [workspace / ".agent-local", output.parent, output, model]:
        if directory.is_symlink():
            raise RuntimeError("Fixture directory must not be a symlink")
        directory.mkdir(parents=True, exist_ok=True)
        directory.resolve().relative_to(workspace / ".agent-local")
    verified = []
    for name, expected_size, expected_digest in ARTIFACTS:
        target = model / name
        if not valid(target, expected_size, expected_digest):
            if target.exists() or target.is_symlink():
                raise RuntimeError("Existing fixture model differs; refusing overwrite: " + name)
            partial = target.with_name(name + ".partial")
            with urllib.request.urlopen(MODEL_URL + "/" + name, timeout=30) as response:
                with partial.open("xb") as handle:
                    total = 0
                    started = time.monotonic()
                    while True:
                        block = response.read(1024 * 1024)
                        if not block:
                            break
                        total += len(block)
                        if total > expected_size or time.monotonic() - started > 120:
                            raise RuntimeError("Bounded model fixture download exceeded expected bytes/time")
                        handle.write(block)
            if not valid(partial, expected_size, expected_digest):
                raise RuntimeError("Pinned model fixture integrity failure: " + name)
            partial.replace(target)
        verified.append({"name": name, "bytes": expected_size, "sha256": expected_digest})
    fixture = output / (UTTERANCE + ".flac")
    compressed_bytes = None
    if not valid(fixture, FLAC_SIZE, FLAC_SHA256):
        if fixture.exists() or fixture.is_symlink():
            raise RuntimeError("Existing speech fixture differs; refusing overwrite")
        audio = None
        reference = None
        with urllib.request.urlopen(ARCHIVE_URL, timeout=30) as response:
            bounded = BoundedPrefix(response)
            with tarfile.open(fileobj=bounded, mode="r|gz") as archive:
                for index, member in enumerate(archive):
                    if index >= 1000 or member.size > 3 * 1024 * 1024:
                        raise RuntimeError("Unexpected bounded official archive shape")
                    if not member.isfile():
                        continue
                    if member.name == MEMBER:
                        audio = archive.extractfile(member).read(member.size)
                    if member.name == TRANSCRIPT_MEMBER:
                        text = archive.extractfile(member).read(member.size).decode("utf-8")
                        for line in text.splitlines():
                            identifier, transcript = line.split(" ", 1)
                            if identifier == UTTERANCE:
                                reference = transcript
                    if audio is not None and reference is not None:
                        break
                compressed_bytes = bounded.total
        if reference != REFERENCE or audio is None or len(audio) != FLAC_SIZE or hashlib.sha256(audio).hexdigest() != FLAC_SHA256:
            raise RuntimeError("Exact licensed speech/reference fixture integrity failed")
        with fixture.open("xb") as handle:
            handle.write(audio)
    receipt = {"modelRevision": REVISION, "models": verified,
               "source": ARCHIVE_URL, "utterance": UTTERANCE, "license": "CC-BY-4.0",
               "attribution": "LibriSpeech: Vassil Panayotov, Daniel Povey; derived from LibriVox public-domain audiobooks",
               "licenseURL": "https://creativecommons.org/licenses/by/4.0/",
               "resourceURL": "https://www.openslr.org/12", "reference": REFERENCE,
               "flacBytes": FLAC_SIZE, "flacSHA256": FLAC_SHA256,
               "archivePrefixBytesRead": compressed_bytes,
               "archiveIntegrityScope": "Only exact selected member/reference verified; no full archive checksum claim",
               "modelDirectory": str(model), "fixturePath": str(fixture)}
    (output / "fixture-receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
