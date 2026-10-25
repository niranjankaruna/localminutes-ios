#!/usr/bin/env python3
"""Pinned public native-summary fixtures; weights/binaries stay ignored.

Run from repository root with Python3. No package installer or paid service.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

FRAMEWORK_URL = "https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip"
FRAMEWORK_SIZE = 74944281
FRAMEWORK_SHA = "c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab"
MODEL_URL = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_SIZE = 1117320736
MODEL_SHA = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
         "huggingface.co", "us.aws.cdn.hf.co"}


def approved(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in HOSTS or parsed.username or parsed.password:
        raise ValueError("Unreviewed distribution route")


class RedirectPolicy(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        approved(new_url)
        return super().redirect_request(request, response, code, message, headers, new_url)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def download(url, target, size, expected):
    if target.is_symlink():
        raise ValueError("Unsafe artifact destination")
    if target.is_file() and target.stat().st_size == size and digest(target) == expected:
        return
    approved(url)
    partial = target.with_suffix(target.suffix + ".part")
    if partial.is_symlink():
        raise ValueError("Unsafe partial artifact destination")
    opener = urllib.request.build_opener(RedirectPolicy())
    value = hashlib.sha256()
    received = 0
    try:
        with opener.open(urllib.request.Request(url, headers={"User-Agent": "LocalMinutes-native-test"}), timeout=150) as response:
            approved(response.url)
            if response.status != 200:
                raise ValueError("Unexpected distribution status")
            with partial.open("wb") as output:
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    received += len(chunk)
                    if received > size:
                        raise ValueError("Oversized public artifact")
                    value.update(chunk)
                    output.write(chunk)
        if received != size or value.hexdigest() != expected:
            raise ValueError("Public artifact integrity mismatch")
        os.replace(partial, target)
    finally:
        partial.unlink(missing_ok=True)


def inside(path, root):
    return path.resolve().is_relative_to(root.resolve())


def extract_framework(archive, destination, research_root):
    if destination.exists():
        # A re-run must not trust a previously extracted mutable native binary.
        if destination.is_symlink() or not inside(destination, research_root):
            raise ValueError("Unsafe existing extraction target")
        shutil.rmtree(destination)
    destination.mkdir()
    pending_links = []
    with zipfile.ZipFile(archive) as source:
        selected = []
        for info in source.infolist():
            parts = PurePosixPath(info.filename).parts
            if "llama.xcframework" not in parts:
                continue
            suffix = parts[parts.index("llama.xcframework") + 1:]
            if not suffix:
                continue
            if any(part in ("", ".", "..") for part in suffix) or info.filename.startswith("/"):
                raise ValueError("Unsafe native archive entry")
            target = destination.joinpath(*suffix)
            if not inside(target, destination):
                raise ValueError("Escaping native archive entry")
            selected.append((info, target))
        for info, target in selected:
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(info.external_attr >> 16):
                pending_links.append((target, source.read(info).decode("utf-8")))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(info) as data, target.open("wb") as output:
                    shutil.copyfileobj(data, output, length=1024 * 1024)
                permissions = (info.external_attr >> 16) & 0o777
                if permissions:
                    target.chmod(permissions)
        for target, link in pending_links:
            if PurePosixPath(link).is_absolute() or not inside(target.parent / link, destination):
                raise ValueError("Unsafe native archive symlink")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(link)
    if not (destination / "Info.plist").is_file():
        raise ValueError("Native framework root missing")


def macho_type(path):
    with path.open("rb") as binary:
        header = binary.read(32)
        if header[:4] == b"\xca\xfe\xba\xbe":
            offset = struct.unpack_from(">I", header, 16)[0]
            binary.seek(offset)
            header = binary.read(16)
        magic = struct.unpack_from("<I", header)[0]
        if magic not in (0xFEEDFACE, 0xFEEDFACF):
            raise ValueError("Unexpected native binary magic")
        return struct.unpack_from("<I", header, 12)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-only", action="store_true",
                        help="Prepare native binaries without downloading an inference model")
    arguments = parser.parse_args()
    workspace = Path.cwd().resolve()
    # The app links both dynamic engines. Prepare the exact Whisper framework
    # for every real build; its model is fetched only by focused ASR checks.
    subprocess.run([sys.executable, str(workspace / "scripts/fixtures/prepare_whisper_fixture.py"),
                    "--framework-only"], check=True)
    root = workspace / ".agent-local" / "native-llm"
    root.mkdir(parents=True, exist_ok=True)
    if not inside(root, workspace) or root.is_symlink():
        raise ValueError("Unsafe native fixture root")
    required_space = 500_000_000 if arguments.framework_only else 2_000_000_000
    if shutil.disk_usage(root).free < required_space:
        raise ValueError("Insufficient space for bounded native fixtures")
    archive = root / "llama-b5046-xcframework.zip"
    model = root / "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    download(FRAMEWORK_URL, archive, FRAMEWORK_SIZE, FRAMEWORK_SHA)
    framework = root / "llama.xcframework"
    extract_framework(archive, framework, root)
    metadata = {"framework": str(framework), "frameworkSHA256": FRAMEWORK_SHA,
                "macOSMachOFileType": macho_type(framework / "macos-arm64_x86_64/llama.framework/Versions/A/llama")}
    if not arguments.framework_only:
        download(MODEL_URL, model, MODEL_SIZE, MODEL_SHA)
        metadata.update({"model": str(model), "modelSHA256": MODEL_SHA, "modelBytesVerified": MODEL_SIZE})
    print(json.dumps(metadata, indent=2))
    if metadata["macOSMachOFileType"] != 6:
        raise ValueError("Expected official MH_DYLIB framework")
    if not arguments.framework_only:
        print("Set LOCALMINUTES_QWEN_MODEL_PATH to the verified model path above.")
        if os.environ.get("GITHUB_ENV"):
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as environment:
                environment.write("LOCALMINUTES_QWEN_MODEL_PATH=" + str(model) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Native fixture preparation failed: " + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
