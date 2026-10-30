"""Private stdio worker: keeps native CUDA failures away from the recording UI."""
from pathlib import Path
import argparse
from importlib import metadata
import json
import os
import re
import struct
import sys

import numpy as np
import sherpa_onnx

from .files import read_json
from .models import Models, SPEECH_FILES, SPEECH_REVISION
from .speech_runtime import prepare_cuda


def audit_placement(raw: bytes):
    text = raw.replace(b"\0", b"").decode("utf-8", errors="replace")
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    policy = read_json(Path(__file__).parent / "resources" / "SpeechCudaPlacement.json")
    if policy["modelRevision"] != SPEECH_REVISION:
        raise ValueError("Speech CUDA placement policy does not match the model.")
    if metadata.version("sherpa-onnx") != policy["runtimeVersion"]:
        raise ValueError("Speech CUDA placement policy does not match the runtime.")
    allowed = {(node["op"], node["name"]) for node in policy["cpuMetadataNodes"]}
    blocks = []
    active = None
    for line in text.splitlines():
        if "VerifyEachNodeIsAssignedToAnEp]" not in line:
            continue
        message = line.split("VerifyEachNodeIsAssignedToAnEp]", 1)[1].strip()
        header = re.fullmatch(r"(?:All nodes|Node\(s\)) placed on \[(\w+)\]\. Number of nodes: (\d+)", message)
        if header:
            active = dict(provider=header[1], count=int(header[2]), nodes=[])
            blocks.append(active)
        elif active and (node := re.fullmatch(r"(\w+) \((.*)\)", message)):
            active["nodes"].append((node[1], node[2]))
    cuda = [block for block in blocks if block["provider"] == "CUDAExecutionProvider"]
    if len(cuda) != policy["cudaSessions"] or any(block["count"] <= 0 for block in cuda):
        raise RuntimeError("Parakeet could not verify CUDA for all three neural graphs. CPU fallback was refused.")
    cpu_nodes = set()
    for block in blocks:
        if block["provider"] == "CPUExecutionProvider":
            if len(block["nodes"]) != block["count"]:
                raise RuntimeError("Incomplete speech placement diagnostics. CPU fallback was refused.")
            cpu_nodes.update(block["nodes"])
        elif block["provider"] != "CUDAExecutionProvider":
            raise RuntimeError("Unexpected speech execution provider.")
    if unexpected := cpu_nodes - allowed:
        raise RuntimeError("Speech neural operations would run on CPU; fallback was refused: " + repr(sorted(unexpected)[:3]))
    return dict(cudaGraphs=len(cuda), cudaNodes=sum(block["count"] for block in cuda), cpuMetadataNodes=len(cpu_nodes))


def emit(value):
    sys.stdout.buffer.write(json.dumps(value, ensure_ascii=False).encode("utf-8") + b"\n")
    sys.stdout.buffer.flush()


def read_exact(count):
    chunks = bytearray()
    while len(chunks) < count:
        block = sys.stdin.buffer.read(count - len(chunks))
        if not block:
            raise EOFError("Speech input pipe closed.")
        chunks.extend(block)
    return bytes(chunks)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--speech-worker", action="store_true")
    parser.add_argument("--model-directory", type=Path, required=True)
    parser.add_argument("--runtime-directory", type=Path, required=True)
    parser.add_argument("--diagnostics", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        for name, size, sha in SPEECH_FILES:
            Models.verify(args.model_directory / name, size, sha)
        provider = prepare_cuda(args.runtime_directory)
        model = args.model_directory
        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(encoder=str(model / "encoder.onnx"), decoder=str(model / "decoder.onnx"),
            joiner=str(model / "joiner.onnx"), tokens=str(model / "tokens.txt"), num_threads=4, sample_rate=16000,
            feature_dim=80, model_type="nemo_transducer", provider=provider)
        placement = audit_placement(args.diagnostics.read_bytes())
        emit(dict(ready=True, placement=placement))
        # Placement is established. Avoid accumulating verbose ORT run logs.
        with open(os.devnull, "wb") as null:
            os.dup2(null.fileno(), 2)
        while True:
            try:
                size = struct.unpack("<I", read_exact(4))[0]
            except EOFError:
                return 0
            if size == 0:
                return 0
            if size % 2 or size > 16 * 1024 * 1024:
                raise ValueError("Invalid speech PCM frame.")
            pcm = read_exact(size)
            stream = recognizer.create_stream()
            stream.accept_waveform(16000, np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768)
            recognizer.decode_stream(stream)
            emit(dict(text=stream.result.text.strip()))
    except Exception as error:
        emit(dict(error=str(error)))
        return 1
