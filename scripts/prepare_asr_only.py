#!/usr/bin/env python3
"""Prepare pinned real sherpa C API libraries on hosted macOS; never strip them."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".agent-local" / "asr-only"
ARTIFACTS = ROOT / "Vendor" / "SherpaASROnly" / "Artifacts"
REVISION = "11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf"
SOURCE_SHA = "0a8db6c55dd318f4a688faba85f7760b99a6c92e8ef8864479d418531bee1ac2"
MAC_NAME = "sherpa-onnx-v1.13.8-osx-universal2-static-no-tts-lib"
MAC_SHA = "7bbaa4bf1c73a68cc9ea126967278873c86eeeb99774b544f3644e0a6200e993"
ORT_NAME = "onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip"
ORT_SHA = "2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599"
LIBRARIES = (
    "libkaldi-native-fbank-core.a", "libkissfft-float.a", "libsherpa-onnx-c-api.a",
    "libsherpa-onnx-core.a", "libsherpa-onnx-fst.a", "libsherpa-onnx-fstfar.a",
    "libsherpa-onnx-kaldifst-core.a", "libkaldi-decoder-core.a", "libssentencepiece_core.a",
)
FLAGS = {
    "BUILD_SHARED_LIBS": "OFF", "SHERPA_ONNX_ENABLE_TTS": "OFF",
    "SHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION": "OFF",
    "SHERPA_ONNX_ENABLE_C_API": "ON", "SHERPA_ONNX_ENABLE_GPU": "OFF",
    "SHERPA_ONNX_ENABLE_PYTHON": "OFF", "SHERPA_ONNX_ENABLE_BINARY": "OFF",
    "SHERPA_ONNX_BUILD_C_API_EXAMPLES": "OFF", "SHERPA_ONNX_ENABLE_TESTS": "OFF",
    "SHERPA_ONNX_ENABLE_CHECK": "OFF", "SHERPA_ONNX_ENABLE_PORTAUDIO": "OFF",
    "SHERPA_ONNX_ENABLE_JNI": "OFF", "SHERPA_ONNX_ENABLE_WEBSOCKET": "OFF",
    "BUILD_PIPER_PHONMIZE_EXE": "OFF", "BUILD_PIPER_PHONMIZE_TESTS": "OFF",
    "BUILD_ESPEAK_NG_EXE": "OFF", "BUILD_ESPEAK_NG_TESTS": "OFF",
}
REQUIRED = ("_SherpaOnnxCreateOnlineRecognizer", "_SherpaOnnxDecodeOnlineStream",
            "_SherpaOnnxOnlineStreamAcceptWaveform", "_SherpaOnnxGetOnlineStreamResult",
            "_SherpaOnnxGetVersionStr")
DEADLINE = None
MAX_DOWNLOAD_BYTES = 512 * 1024 * 1024


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(args, **kwargs):
    remaining = int(DEADLINE - time.monotonic()) if DEADLINE else 2400
    if remaining <= 0:
        raise TimeoutError("ASR preparation exceeded its 40-minute bound")
    print("+ " + " ".join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, timeout=remaining,
                          text=True, **kwargs)


def fetch(name, url, sha):
    path = WORK / "downloads" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        cached = ROOT / ".agent-local" / "licenses" / name
        if cached.is_file() and digest(cached) == sha:
            shutil.copyfile(cached, path)
        else:
            temporary = path.with_suffix(path.suffix + ".partial")
            remaining = DEADLINE - time.monotonic() if DEADLINE else 2400
            if remaining <= 0:
                raise TimeoutError("ASR preparation exceeded its 40-minute bound")
            # A network read is bounded separately from the overall preparation
            # deadline. Check every chunk so a slowly progressing response cannot
            # keep the job alive indefinitely or exhaust runner storage.
            with urllib.request.urlopen(url, timeout=min(30, remaining)) as response, temporary.open("wb") as target:
                declared = response.headers.get("Content-Length")
                if declared is not None and int(declared) > MAX_DOWNLOAD_BYTES:
                    raise ValueError(f"Download exceeds 512 MiB: {name}")
                total = 0
                while True:
                    if DEADLINE and time.monotonic() >= DEADLINE:
                        raise TimeoutError("ASR preparation exceeded its 40-minute bound")
                    chunk = response.read1(64 * 1024)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_DOWNLOAD_BYTES:
                        raise ValueError(f"Download exceeds 512 MiB: {name}")
                    target.write(chunk)
            if digest(temporary) != sha:
                raise ValueError(f"SHA-256 mismatch: {name}")
            temporary.replace(path)
    if digest(path) != sha:
        raise ValueError(f"SHA-256 mismatch: {name}")
    return path


def extract_tar(archive, parent):
    # Only regular files/directories are needed; never follow archive links.
    with tarfile.open(archive) as source:
        for member in source:
            path = parent / member.name
            if not path.resolve().is_relative_to(parent.resolve()):
                raise ValueError("Unsafe archive member")
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                path.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as data, path.open("wb") as output:
                    shutil.copyfileobj(data, output)
            elif member.issym() or member.islnk():
                # The pinned source uses links outside our build paths; preserve
                # no links rather than trusting archive-controlled destinations.
                continue
            else:
                raise ValueError("Unsupported archive member")


def source_tree():
    archive = fetch(f"sherpa-source-{REVISION}.tar.gz",
                    f"https://codeload.github.com/k2-fsa/sherpa-onnx/tar.gz/{REVISION}", SOURCE_SHA)
    parent = WORK / "source"
    parent.mkdir(parents=True, exist_ok=True)
    # Always re-extract checked bytes so a stale/modified build tree is not input.
    with tarfile.open(archive) as content:
        top = content.getmembers()[0].name.split("/")[0]
    if top != f"sherpa-onnx-{REVISION}":
        raise ValueError(f"Unexpected pinned source archive root: {top}")
    destination = parent / top
    if destination.exists():
        shutil.rmtree(destination)
    extract_tar(archive, parent)
    if 'set(SHERPA_ONNX_VERSION "1.13.8")' not in (destination / "CMakeLists.txt").read_text():
        raise ValueError("Unexpected sherpa version")
    return destination


def verify_binary(binary, architectures):
    actual = run(["xcrun", "lipo", "-archs", binary], capture_output=True).stdout.split()
    if sorted(actual) != sorted(architectures):
        raise ValueError(f"Unexpected architectures: {actual}")
    checks = {}
    for arch in architectures:
        symbols = run(["xcrun", "nm", "-arch", arch, "-gU", binary], capture_output=True).stdout
        names = {line.split()[-1] for line in symbols.splitlines() if line.split()}
        missing = set(REQUIRED) - names
        forbidden = sorted(name for name in names if name.startswith("_espeak")
                           or "piper" in name.lower() or "phonemize_eSpeak" in name)
        if missing or forbidden:
            raise ValueError(f"{arch}: missing {missing}; forbidden {forbidden}")
        checks[arch] = {"requiredCPUEntryPoints": list(REQUIRED), "forbiddenDefinitions": forbidden}
    return checks


def framework(output, libraries, header, platform, architectures):
    output.mkdir(parents=True)
    (output / "Headers" / "sherpa-onnx" / "c-api").mkdir(parents=True)
    (output / "Modules").mkdir()
    shutil.copyfile(header, output / "Headers" / "sherpa-onnx" / "c-api" / "c-api.h")
    (output / "Modules" / "module.modulemap").write_text(
        'framework module SherpaOnnxC {\n header "sherpa-onnx/c-api/c-api.h"\n export *\n}\n')
    info = {"CFBundleIdentifier": "com.k2-fsa.sherpa-onnx", "CFBundleName": "SherpaOnnxC",
            "CFBundlePackageType": "FMWK", "CFBundleExecutable": "SherpaOnnxC",
            "CFBundleVersion": "1.13.8", "CFBundleShortVersionString": "1.13.8",
            "CFBundleSupportedPlatforms": [platform],
            "MinimumOSVersion": "15.0" if platform == "MacOSX" else "18.0"}
    with (output / "Info.plist").open("wb") as target:
        plistlib.dump(info, target)
    run(["xcrun", "libtool", "-static", "-o", output / "SherpaOnnxC", *libraries])
    return {"mergedInputs": [{"name": path.name, "sha256": digest(path)} for path in libraries],
            "binarySHA256": digest(output / "SherpaOnnxC"),
            "symbolChecks": verify_binary(output / "SherpaOnnxC", architectures)}


def create_xcframework(name, frameworks, receipt):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    # Build in a fresh same-volume directory, then replace the generated output.
    staging = Path(tempfile.mkdtemp(prefix="asr-", dir=ARTIFACTS))
    candidate = staging / f"{name}.xcframework"
    try:
        args = ["xcodebuild", "-create-xcframework"]
        for item in frameworks:
            args += ["-framework", item]
        run([*args, "-output", candidate])
        receipt["outputFiles"] = {str(p.relative_to(candidate)): digest(p)
                                  for p in sorted(candidate.rglob("*")) if p.is_file()}
        destination = ARTIFACTS / candidate.name
        if destination.exists():
            shutil.rmtree(destination)
        candidate.replace(destination)
        (ARTIFACTS / f"{name}.receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    finally:
        shutil.rmtree(staging)


def prepare_macos(source, receipt):
    archive = fetch(f"{MAC_NAME}.tar.bz2",
                    f"https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/{MAC_NAME}.tar.bz2", MAC_SHA)
    parent = WORK / "macos"
    parent.mkdir(parents=True, exist_ok=True)
    extract_tar(archive, parent)
    output = parent / "SherpaOnnxC.framework"
    if output.exists():
        shutil.rmtree(output)
    receipt.update({"origin": "publisher universal2 static-no-tts library distribution",
                    "archiveSHA256": digest(archive), "buildFlags": "publisher flags not fully attested"})
    receipt["slices"] = {"macos": framework(output, [parent / MAC_NAME / "lib" / n for n in LIBRARIES],
        source / "sherpa-onnx" / "c-api" / "c-api.h", "MacOSX", ["arm64", "x86_64"])}
    return [output], receipt


def prepare_ios(source, receipt, jobs):
    archive = fetch(ORT_NAME,
        f"https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/{ORT_NAME}", ORT_SHA)
    ort = WORK / "ort-ios"
    ort.mkdir(parents=True, exist_ok=True)
    # Extract only files; the verified ORT XCFramework contains regular bundles.
    with zipfile.ZipFile(archive) as content:
        for item in content.infolist():
            if not (ort / item.filename).resolve().is_relative_to(ort.resolve()):
                raise ValueError("Unsafe ORT ZIP member")
        content.extractall(ort)
    slices = {}
    for name, platform, ort_slice in [("os64", "OS64", "ios-arm64"),
            ("simulator_arm64", "SIMULATORARM64", "ios-arm64_x86_64-simulator"),
            ("simulator_x86_64", "SIMULATOR64", "ios-arm64_x86_64-simulator")]:
        build = WORK / "ios" / name
        env = os.environ.copy()
        env["SHERPA_ONNXRUNTIME_LIB_DIR"] = str(ort / "onnxruntime.xcframework" / ort_slice)
        env["SHERPA_ONNXRUNTIME_INCLUDE_DIR"] = str(Path(env["SHERPA_ONNXRUNTIME_LIB_DIR"]) / "onnxruntime.framework" / "Headers")
        config = ["cmake", "-S", source, "-B", build,
            f"-DCMAKE_TOOLCHAIN_FILE={source / 'toolchains' / 'ios.toolchain.cmake'}",
            f"-DPLATFORM={platform}", "-DENABLE_BITCODE=0", "-DENABLE_ARC=1",
            "-DENABLE_VISIBILITY=0", "-DDEPLOYMENT_TARGET=18.0", "-DCMAKE_BUILD_TYPE=Release",
            *[f"-D{k}={v}" for k, v in FLAGS.items()]]
        run(config, env=env)
        cache = (build / "CMakeCache.txt").read_text()
        for key, value in FLAGS.items():
            if not re.search(rf"^{key}:[^=]+={value}$", cache, re.MULTILINE):
                raise ValueError(f"CMake did not retain required flag {key}={value}")
        run(["cmake", "--build", build, "--parallel", jobs], env=env)
        if any("espeak" in p.name.lower() or "piper" in p.name.lower() or p.name == "libucd.a"
               for p in (build / "lib").glob("*.a")):
            raise ValueError("TTS archive built despite ASR-only configuration")
        slices[name] = build
    combined = WORK / "ios" / "simulator"
    combined.mkdir(parents=True, exist_ok=True)
    for name in LIBRARIES:
        run(["xcrun", "lipo", "-create", slices["simulator_arm64"] / "lib" / name,
             slices["simulator_x86_64"] / "lib" / name, "-output", combined / name])
    header = source / "sherpa-onnx" / "c-api" / "c-api.h"
    frameworks, details = [], {}
    for name, libs, platform, archs in [
        ("device", slices["os64"] / "lib", "iPhoneOS", ["arm64"]),
        ("simulator", combined, "iPhoneSimulator", ["arm64", "x86_64"])]:
        output = WORK / "ios" / name / "SherpaOnnxC.framework"
        if output.exists():
            shutil.rmtree(output)
        details[name] = framework(output, [libs / n for n in LIBRARIES], header, platform, archs)
        frameworks.append(output)
    receipt.update({"origin": "pinned source build", "buildFlags": FLAGS, "ortArchiveSHA256": ORT_SHA,
        "slices": details, "cmakeCaches": {n: digest(p / "CMakeCache.txt") for n, p in slices.items()},
        "dependencyCMakeFiles": {str(p.relative_to(source)): digest(p)
                                 for p in sorted((source / "cmake").rglob("*.cmake"))},
        "dependencySourceFiles": {str(p.relative_to(WORK / "ios")): digest(p)
             for p in sorted((WORK / "ios").rglob("*-src/CMakeLists.txt"))}})
    return frameworks, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("ios", "macos", "all"), default="all")
    parser.add_argument("--jobs", type=int, default=3)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Native framework preparation requires hosted macOS/Xcode")
    if not 1 <= args.jobs <= 8:
        parser.error("--jobs must be between 1 and 8")
    global DEADLINE
    DEADLINE = time.monotonic() + 2400
    # macOS process-wide deadline also interrupts blocked network/filesystem
    # work; chunk checks and subprocess timeouts give ordinary clear failures.
    def deadline_expired(_signum, _frame):
        raise TimeoutError("ASR preparation exceeded its 40-minute bound")
    signal.signal(signal.SIGALRM, deadline_expired)
    signal.alarm(2400)
    source = source_tree()
    receipt = {"schemaVersion": 1, "sherpaVersion": "1.13.8", "sourceRevision": REVISION,
        "sourceArchiveSHA256": SOURCE_SHA, "onnxRuntimeVersion": "1.28.2",
        "headerSHA256": digest(source / "sherpa-onnx" / "c-api" / "c-api.h"),
        "xcode": run(["xcodebuild", "-version"], capture_output=True).stdout.strip(),
        "clang": run(["xcrun", "clang", "--version"], capture_output=True).stdout.strip()}
    frameworks, platforms = [], {}
    if args.platform in ("macos", "all"):
        built, details = prepare_macos(source, dict(receipt))
        frameworks.extend(built)
        platforms["macos"] = details
    if args.platform in ("ios", "all"):
        built, details = prepare_ios(source, dict(receipt), args.jobs)
        frameworks.extend(built)
        platforms["ios"] = details
    receipt["platforms"] = platforms
    create_xcframework("SherpaOnnxC", frameworks, receipt)
    # Reject an incompatible local package declaration before later jobs spend
    # time fetching model weights. This compiles metadata, not model behavior.
    run(["swift", "package", "--package-path", ROOT / "Vendor" / "SherpaASROnly",
         "dump-package"], capture_output=True)
    receipt["swiftPackageManifestSHA256"] = digest(ROOT / "Vendor" / "SherpaASROnly" / "Package.swift")
    receipt["swiftPackageManifestValidated"] = True
    (ARTIFACTS / "SherpaOnnxC.receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
