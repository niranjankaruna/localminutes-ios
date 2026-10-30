#!/usr/bin/env python3
"""Pinned public native-summary fixtures; weights/binaries stay ignored.

Run from repository root with Python3. No package installer or paid service.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

FRAMEWORK_URL = "https://github.com/ggml-org/llama.cpp/releases/download/b11900/llama-b11900-xcframework.zip"
FRAMEWORK_SIZE = 68145160
FRAMEWORK_SHA = "613d22312cecd3915ae3edc167e95dbd37397bdb9f89ff645767622bc8eed222"
# b11900's official binary archive no longer includes an iOS Simulator slice.
# Build that slice only from this exact, independently downloaded source ZIP.
SOURCE_URL = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/b11900.zip"
SOURCE_COMMIT = "74b104c9ba5717116b7e65e0cd35397778653304"
SOURCE_SIZE = 40564305
SOURCE_SHA = "5be8dce16b23c18320d3c6d4e43ae08bd5ae5547b7f9dd8c8e2afc531d7babb6"
MODEL_URL = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_SIZE = 1117320736
MODEL_SHA = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
         "codeload.github.com", "huggingface.co", "us.aws.cdn.hf.co"}


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


def extract_source(archive, destination, research_root):
    """Extract only regular entries from the hash-pinned upstream source ZIP."""
    if destination.is_symlink() or not inside(destination, research_root):
        raise ValueError("Unsafe native source target")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir()
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if len(entries) > 50_000 or sum(item.file_size for item in entries) > 500_000_000:
            raise ValueError("Oversized native source archive")
        for entry in entries:
            # ZipInfo normalizes Windows backslashes and truncates NULs in
            # filename. Validate its unmodified archive spelling first.
            raw_name = entry.orig_filename
            if "\\" in raw_name or "\0" in raw_name:
                raise ValueError("Unsafe native source entry")
            parts = PurePosixPath(raw_name).parts
            if not parts or parts[0] != "llama.cpp-b11900":
                raise ValueError("Unexpected native source root")
            suffix = parts[1:]
            if not suffix:
                continue
            if any(part in ("", ".", "..") for part in suffix):
                raise ValueError("Unsafe native source entry")
            target = destination.joinpath(*suffix)
            if not inside(target, destination) or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Escaping native source entry")
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(entry) as data, target.open("wb") as output:
                    shutil.copyfileobj(data, output, length=1024 * 1024)
                permissions = (entry.external_attr >> 16) & 0o777
                if permissions:
                    target.chmod(permissions)


def add_simulator_slice(framework, root):
    if sys.platform != "darwin":
        raise ValueError("The iOS Simulator slice requires macOS and Xcode")
    archive = root / "llama-b11900-source.zip"
    download(SOURCE_URL, archive, SOURCE_SIZE, SOURCE_SHA)
    source = root / "llama-source-b11900"
    extract_source(archive, source, root)
    # The official script builds both Apple Silicon and Intel simulators and
    # packages the native Metal library and all C headers correctly.
    subprocess.run(["bash", "build-xcframework.sh", "ios-sim"], cwd=source, check=True)
    simulator = source / "build-ios-sim" / "framework" / "llama.framework"
    if macho_type(simulator / "llama") != 6:
        raise ValueError("Expected simulator MH_DYLIB framework")
    device = framework / "ios-arm64" / "llama.framework"
    if digest(simulator / "Headers" / "llama.h") != digest(device / "Headers" / "llama.h"):
        raise ValueError("Simulator and official binary API mismatch")
    combined = root / "llama-combined.xcframework"
    if combined.is_symlink() or not inside(combined, root):
        raise ValueError("Unsafe combined framework target")
    if combined.exists():
        shutil.rmtree(combined)
    arguments = ["xcrun", "xcodebuild", "-create-xcframework"]
    for identifier in ("ios-arm64", "macos-arm64_x86_64"):
        arguments += ["-framework", str(framework / identifier / "llama.framework"),
                      "-debug-symbols", str(framework / identifier / "dSYMs" / "llama.dSYM")]
    arguments += ["-framework", str(simulator), "-debug-symbols",
                  str(source / "build-ios-sim" / "dSYMs" / "llama.dSYM"), "-output", str(combined)]
    subprocess.run(arguments, check=True)
    with (combined / "Info.plist").open("rb") as handle:
        libraries = plistlib.load(handle)["AvailableLibraries"]
    if not any(item.get("SupportedPlatform") == "ios"
               and item.get("SupportedPlatformVariant") == "simulator" for item in libraries):
        raise ValueError("Combined framework is missing the simulator")
    if framework.is_symlink() or not inside(framework, root):
        raise ValueError("Unsafe framework replacement target")
    shutil.rmtree(framework)
    combined.rename(framework)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework-only", action="store_true",
                        help="Prepare native binaries without downloading an inference model")
    parser.add_argument("--with-simulator", action="store_true",
                        help="Build and add the matching iOS Simulator slice (requires macOS, Xcode and CMake)")
    arguments = parser.parse_args()
    workspace = Path.cwd().resolve()
    root = workspace / ".agent-local" / "native-llm"
    root.mkdir(parents=True, exist_ok=True)
    if not inside(root, workspace) or root.is_symlink():
        raise ValueError("Unsafe native fixture root")
    required_space = 7_000_000_000 if arguments.with_simulator else (
        500_000_000 if arguments.framework_only else 2_000_000_000)
    if shutil.disk_usage(root).free < required_space:
        raise ValueError("Insufficient space for bounded native fixtures")
    archive = root / "llama-b11900-xcframework.zip"
    model = root / "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    download(FRAMEWORK_URL, archive, FRAMEWORK_SIZE, FRAMEWORK_SHA)
    framework = root / "llama.xcframework"
    extract_framework(archive, framework, root)
    if arguments.with_simulator:
        add_simulator_slice(framework, root)
    metadata = {"framework": str(framework), "frameworkSHA256": FRAMEWORK_SHA,
                "macOSMachOFileType": macho_type(framework / "macos-arm64_x86_64/llama.framework/Versions/A/llama")}
    if arguments.with_simulator:
        metadata.update({"simulatorSourceSHA256": SOURCE_SHA, "simulatorSourceCommit": SOURCE_COMMIT})
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
