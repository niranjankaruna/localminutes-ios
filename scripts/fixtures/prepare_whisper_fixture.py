#!/usr/bin/env python3
"""Pinned Whisper Apple binary/tiny-English/CC-BY audio; all bytes stay ignored."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import urllib.request
import zipfile

import prepare_native_summary as native
import prepare_native_fixture as speech

FRAMEWORK_URL = "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.5/whisper-v1.7.5-xcframework.zip"
FRAMEWORK_SIZE = 37754339
FRAMEWORK_SHA = "c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a"
SOURCE = "51c6961c7b64b406833f4b6a4a20e67142f69225"
MODEL_REVISION = "5359861c739e955e79d9a303bcbc70fb988958b1"
MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/" + MODEL_REVISION + "/ggml-tiny.en.bin"
MODEL_SIZE = 77704715
MODEL_SHA = "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"


def extract(archive, destination, root):
    if destination.is_symlink() or not native.inside(destination, root):
        raise ValueError("Unsafe Whisper extraction destination")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir()
    links = []
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            parts = PurePosixPath(entry.filename).parts
            if "whisper.xcframework" not in parts:
                continue
            suffix = parts[parts.index("whisper.xcframework") + 1:]
            if not suffix:
                continue
            if entry.filename.startswith("/") or any(part in ("", ".", "..") or ":" in part for part in suffix):
                raise ValueError("Unsafe Whisper archive member")
            target = destination.joinpath(*suffix)
            if not native.inside(target, destination):
                raise ValueError("Escaping Whisper archive member")
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(entry.external_attr >> 16):
                links.append((target, source.read(entry).decode("utf-8")))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(entry) as data, target.open("wb") as output:
                    shutil.copyfileobj(data, output, length=1024 * 1024)
                mode = (entry.external_attr >> 16) & 0o777
                if mode:
                    target.chmod(mode)
        for target, link in links:
            if PurePosixPath(link).is_absolute() or not native.inside(target.parent / link, destination):
                raise ValueError("Escaping Whisper archive link")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(link)
    if not (destination / "Info.plist").is_file():
        raise ValueError("Missing Whisper framework root")


def small_text(url, target, marker, expected_sha=None):
    native.approved(url)
    opener = urllib.request.build_opener(native.RedirectPolicy())
    with opener.open(url, timeout=30) as response:
        native.approved(response.url)
        data = response.read(16_385)
    if not data or len(data) > 16_384 or marker not in data.decode("utf-8") or target.is_symlink():
        raise ValueError("Unexpected pinned license/notice")
    actual_sha = hashlib.sha256(data).hexdigest()
    if expected_sha is not None and actual_sha != expected_sha:
        raise ValueError("Pinned license/notice integrity mismatch")
    target.write_bytes(data)
    return actual_sha


def audio_fixture(target, workspace):
    if speech.valid(target, speech.FLAC_SIZE, speech.FLAC_SHA256):
        return
    if target.exists() or target.is_symlink():
        raise ValueError("Unverified existing Whisper audio")
    previous = workspace / ".agent-local/asr-evaluation/native-fixtures/6930-75918-0000.flac"
    if speech.valid(previous, speech.FLAC_SIZE, speech.FLAC_SHA256):
        shutil.copyfile(previous, target)
        return
    audio = reference = None
    opener = urllib.request.build_opener(native.RedirectPolicy())
    with opener.open(speech.ARCHIVE_URL, timeout=30) as response:
        native.approved(response.url)
        with tarfile.open(fileobj=speech.BoundedPrefix(response), mode="r|gz") as archive:
            for index, member in enumerate(archive):
                if index >= 1000 or member.size > 3 * 1024 * 1024:
                    raise ValueError("Unexpected bounded licensed archive prefix")
                if not member.isfile():
                    continue
                if member.name == speech.MEMBER:
                    audio = archive.extractfile(member).read(member.size)
                if member.name == speech.TRANSCRIPT_MEMBER:
                    for line in archive.extractfile(member).read(member.size).decode("utf-8").splitlines():
                        identifier, text = line.split(" ", 1)
                        if identifier == speech.UTTERANCE:
                            reference = text
                if audio is not None and reference is not None:
                    break
    if reference != speech.REFERENCE or audio is None or len(audio) != speech.FLAC_SIZE or hashlib.sha256(audio).hexdigest() != speech.FLAC_SHA256:
        raise ValueError("Licensed fixture integrity mismatch")
    with target.open("xb") as output:
        output.write(audio)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-only", action="store_true")
    arguments = parser.parse_args()
    workspace = Path.cwd().resolve()
    root = workspace / ".agent-local/whisper-fixtures"
    if (workspace / ".agent-local").is_symlink() or root.is_symlink() or not native.inside(root, workspace):
        raise ValueError("Unsafe Whisper fixture root")
    root.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(root).free < 500_000_000:
        raise ValueError("Insufficient bounded fixture space")
    native.HOSTS.update({"raw.githubusercontent.com", "cas-bridge.xethub.hf.co", "cdn-lfs.huggingface.co",
                         "cdn-lfs-us-1.hf.co", "www.openslr.org"})
    archive = root / "whisper-v1.7.5-xcframework.zip"
    native.download(FRAMEWORK_URL, archive, FRAMEWORK_SIZE, FRAMEWORK_SHA)
    framework = root / "whisper.xcframework"
    extract(archive, framework, root)
    binary = framework / "macos-arm64_x86_64/whisper.framework/Versions/A/whisper"
    if native.macho_type(binary) != 6:
        raise ValueError("Expected official dynamic Whisper framework")
    notice_sha = small_text("https://raw.githubusercontent.com/ggml-org/whisper.cpp/" + SOURCE + "/LICENSE",
                            root / "LICENSE-whisper.txt", "Permission is hereby granted",
                            "e562a2ddfaf8280537795ac5ecd34e3012b6582a147ef69ba6a6a5c08c84757d")
    values = {"LOCALMINUTES_WHISPER_FRAMEWORK_PATH": str(framework)}
    receipt = {"sourceRevision": SOURCE, "frameworkBytesVerified": FRAMEWORK_SIZE,
               "frameworkSHA256": FRAMEWORK_SHA, "codeLicense": "MIT", "codeLicenseSHA256Actual": notice_sha}
    if not arguments.framework_only:
        model = root / "ggml-tiny.en.bin"
        native.download(MODEL_URL, model, MODEL_SIZE, MODEL_SHA)
        card_sha = small_text("https://huggingface.co/ggerganov/whisper.cpp/resolve/" + MODEL_REVISION + "/README.md",
                              root / "MODEL_CARD.txt", "license: mit",
                              "21fd967098804f33fc84e803fb0e5ab7666d71801f4027cf28a65e7af09c1758")
        audio = root / "6930-75918-0000.flac"
        audio_fixture(audio, workspace)
        values.update({"LOCALMINUTES_WHISPER_MODEL_PATH": str(model), "LOCALMINUTES_WHISPER_FIXTURE_PATH": str(audio)})
        receipt.update({"modelRevision": MODEL_REVISION, "modelBytesVerified": MODEL_SIZE, "modelSHA256": MODEL_SHA,
            "publishedModelLicense": "MIT", "modelCardSHA256Actual": card_sha,
            "audioBytesVerified": speech.FLAC_SIZE, "audioSHA256": speech.FLAC_SHA256,
            "audioLicense": "CC-BY-4.0", "audioAttribution": "LibriSpeech: Vassil Panayotov, Daniel Povey; LibriVox source",
            "audioSource": speech.ARCHIVE_URL, "audioLicenseURL": "https://creativecommons.org/licenses/by/4.0/"})
    (root / "verified-fixtures.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            for name, value in values.items():
                output.write(name + "=" + value + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Whisper fixture preparation failed: " + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
