"""Prepare pinned Parakeet v2 or v3 Core ML assets and licensed audio.

No inference. Weights and audio stay in ignored fixture directories.
"""
import argparse
from pathlib import Path
import hashlib
import json
import tarfile
import time
import urllib.request
from prepare_native_fixture import (BoundedPrefix, ARCHIVE_URL, MEMBER,
    TRANSCRIPT_MEMBER, UTTERANCE, REFERENCE, FLAC_SIZE, FLAC_SHA256)

REPOSITORY = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
REVISION = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
SOURCE_COMMIT = "c79c4106b954f81205113c3343e5a7e59a1089b5"
ARTIFACTS = [
    ("Decoder.mlmodelc/analytics/coremldata.bin", 243, "46de1a6fe2e49d19a2125bc91acf020df7f2aea84ba821532aade8427a440b05"),
    ("Decoder.mlmodelc/coremldata.bin", 554, "d200ca07694a347f6d02a3886a062ae839831e094e443222f2e48a14945966a8"),
    ("Decoder.mlmodelc/metadata.json", 3427, "90a279b822496316458febc0ce761ab05954fadd9d66aa97bea077a35fc8f2b2"),
    ("Decoder.mlmodelc/model.mil", 13106, "7b95a5a6b672c652000348a67b6d4d92bb8e176b978c6666fe73c28a4d7ec579"),
    ("Decoder.mlmodelc/weights/weight.bin", 14429952, "27d26890221d82322c1092fd99d7b40578e435d5cf4b83c887c42603caf97aba"),
    ("Encoder.mlmodelc/analytics/coremldata.bin", 243, "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105"),
    ("Encoder.mlmodelc/coremldata.bin", 485, "4def7aa848599ad0e17a8b9a982edcdbf33cf92e1f4b798de32e2ca0bc74b030"),
    ("Encoder.mlmodelc/metadata.json", 2926, "58222fbc48c13c49d9715567803cd50cb9c23e4360462e0f8ffcea59a2c73c63"),
    ("Encoder.mlmodelc/model.mil", 959769, "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808"),
    ("Encoder.mlmodelc/weights/weight.bin", 445187200, "4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e"),
    ("JointDecision.mlmodelc/analytics/coremldata.bin", 243, "f1183ba213bb94a918c8d2cad19ab045320618f97f6ca662245b3936d7b090f7"),
    ("JointDecision.mlmodelc/coremldata.bin", 534, "e2c6752f1c8cf2d3f6f26ec93195c9bfa759ad59edf9f806696a138154f96f11"),
    ("JointDecision.mlmodelc/metadata.json", 2936, "ba8d309417b9acd4a175fdb15687de6a941db2f5b06666a60e7cf3cc8e2d3c3c"),
    ("JointDecision.mlmodelc/model.mil", 9722, "93bf82042235127cb81ab537dcae47a1c2e7e242ce4ffdaf772981b45eedc4f0"),
    ("JointDecision.mlmodelc/weights/weight.bin", 3453388, "ca22a65903a05e64137677da608077578a8606090a598abf4875fa6199aaa19d"),
    ("Preprocessor.mlmodelc/analytics/coremldata.bin", 243, "03ab3c1327a054c54c07a40325db967ec574f2c91dcc8192bfa44aa561bcf2d8"),
    ("Preprocessor.mlmodelc/coremldata.bin", 494, "d88ea1fc349459c9e100d6a96688c5b29a1f0d865f544be103001724b986b6d6"),
    ("Preprocessor.mlmodelc/metadata.json", 2974, "fb16c581ff5e1b962e7cb2181ed892cd32f9f84c12b6e80ff3e089f28e35bcbb"),
    ("Preprocessor.mlmodelc/model.mil", 27166, "3e06d16fd061294c8a75be68c43a3b1ed1f593d4a9c35249e9cdbccadc59721e"),
    ("Preprocessor.mlmodelc/weights/weight.bin", 298880, "a5f7df6c7f47147ae9486fe18cc7792f9a44d093ec3c6a11e91ef2dc363c48dc"),
    ("parakeet_vocab.json", 18762, "57019fe3c745772ca83a1b048a4bb951cd51329504ea33d4d83316b96e279a97"),
]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def valid(path, size, digest):
    return path.is_file() and not path.is_symlink() and path.stat().st_size == size and sha256(path) == digest


def owned_directory(path, ignored_root):
    if path.is_symlink():
        raise RuntimeError("Fixture directory cannot be a symlink")
    path.mkdir(parents=True, exist_ok=True)
    path.resolve().relative_to(ignored_root.resolve())


def prepare_audio(output):
    fixture = output / (UTTERANCE + ".flac")
    if valid(fixture, FLAC_SIZE, FLAC_SHA256):
        return fixture
    if fixture.exists() or fixture.is_symlink():
        raise RuntimeError("Existing speech fixture differs; refusing overwrite")
    # Prefer the independently verified fixture already prepared by another
    # mandatory ASR job; no model from that job is loaded or downloaded here.
    cached = Path.cwd() / ".agent-local/asr-evaluation/native-fixtures" / fixture.name
    if valid(cached, FLAC_SIZE, FLAC_SHA256):
        with fixture.open("xb") as handle:
            handle.write(cached.read_bytes())
        return fixture
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
                elif member.name == TRANSCRIPT_MEMBER:
                    for line in archive.extractfile(member).read(member.size).decode("utf-8").splitlines():
                        identifier, transcript = line.split(" ", 1)
                        if identifier == UTTERANCE:
                            reference = transcript
                if audio is not None and reference is not None:
                    break
    if reference != REFERENCE or audio is None or len(audio) != FLAC_SIZE or hashlib.sha256(audio).hexdigest() != FLAC_SHA256:
        raise RuntimeError("Exact licensed speech/reference fixture integrity failed")
    with fixture.open("xb") as handle:
        handle.write(audio)
    return fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", choices=("v2", "v3"), default="v2")
    arguments = parser.parse_args()
    workspace = Path.cwd().resolve()
    if not (workspace / "project.yml").is_file() or not (workspace / "Package.swift").is_file():
        raise RuntimeError("Run from the LocalMinutes repository root")
    ignored = workspace / ".agent-local"
    if ignored.is_symlink():
        raise RuntimeError("Ignored workspace root cannot be a symlink")
    ignored.mkdir(exist_ok=True)
    repository, revision, artifacts = REPOSITORY, REVISION, ARTIFACTS
    if arguments.version == "v3":
        pack = json.loads((workspace / "Tests/Fixtures/Parakeet/parakeet-v3.modelpack.json").read_text(encoding="utf-8"))
        repository = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        revision = pack["revision"]
        if pack["upstreamRepository"] != "https://huggingface.co/" + repository:
            raise RuntimeError("Unexpected v3 fixture repository")
        artifacts = [(item["fileName"], item["byteCount"], item["sha256"]) for item in pack["artifacts"]]
    output = ignored / ("parakeet-coreml-fixtures" if arguments.version == "v2" else "parakeet-v3-fixtures")
    model = output / "model"
    owned_directory(output, ignored)
    owned_directory(model, ignored)
    started = time.monotonic()
    verified = []
    for name, size, digest in artifacts:
        if Path(name).is_absolute() or ".." in Path(name).parts or "\\" in name:
            raise RuntimeError("Unsafe model artifact path")
        target = model / name
        parent = model
        for part in Path(name).parts[:-1]:
            parent = parent / part
            owned_directory(parent, ignored)
        target.resolve().relative_to(model.resolve())
        if not valid(target, size, digest):
            if target.exists() or target.is_symlink():
                raise RuntimeError("Existing model asset differs; refusing overwrite: " + name)
            partial = target.with_name(target.name + ".partial")
            url = "https://huggingface.co/" + repository + "/resolve/" + revision + "/" + name
            with urllib.request.urlopen(url, timeout=30) as response:
                with partial.open("xb") as handle:
                    received = 0
                    while True:
                        block = response.read(1024 * 1024)
                        if not block:
                            break
                        received += len(block)
                        if received > size or time.monotonic() - started > 900:
                            raise RuntimeError("Pinned model download exceeded byte/time bound")
                        handle.write(block)
            if not valid(partial, size, digest):
                raise RuntimeError("Exact native model asset failed SHA256 verification: " + name)
            partial.replace(target)
        verified.append({"path": name, "bytes": size, "sha256": digest})
    expected = {name for name, _, _ in artifacts}
    actual = {str(p.relative_to(model)).replace("\\", "/") for p in model.rglob("*") if p.is_file()}
    if actual != expected:
        raise RuntimeError("Native model directory contains unexpected files")
    fixture = prepare_audio(output)
    receipt = {"repository": repository, "modelRevision": revision,
        "runtimeSourceCommit": SOURCE_COMMIT, "modelBytes": sum(a[1] for a in artifacts),
        "models": verified, "modelDirectory": str(model), "fixturePath": str(fixture),
        "license": "CC-BY-4.0", "modelAttribution": "NVIDIA Parakeet TDT " + arguments.version + "; Core ML conversion by FluidInference",
        "speechSource": ARCHIVE_URL, "speechUtterance": UTTERANCE,
        "speechAttribution": "LibriSpeech: Vassil Panayotov and Daniel Povey; LibriVox source",
        "speechReference": REFERENCE, "speechBytes": FLAC_SIZE, "speechSHA256": FLAC_SHA256,
        "inferenceExecuted": False}
    (output / "fixture-receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
