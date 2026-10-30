from importlib import metadata
import io
from types import SimpleNamespace

import pytest

from localminutes import speech_worker, speech_client, speech_runtime
from localminutes.models import SPEECH_REVISION


@pytest.fixture
def placement_policy(monkeypatch):
    monkeypatch.setattr(speech_worker, "read_json", lambda path: dict(modelRevision=SPEECH_REVISION,
        runtimeVersion=metadata.version("sherpa-onnx"), cudaSessions=3, cpuMetadataNodes=[dict(op="Shape", name="length")]))


def log_line(message):
    return "[V:onnxruntime:, session_state.cc:1313 onnxruntime::VerifyEachNodeIsAssignedToAnEp] " + message + "\n"


def gpu_blocks():
    return log_line("All nodes placed on [CUDAExecutionProvider]. Number of nodes: 12") * 3


def test_speech_audit_accepts_only_known_cpu_metadata(placement_policy):
    raw = gpu_blocks() + log_line("Node(s) placed on [CPUExecutionProvider]. Number of nodes: 1") + log_line("Shape (length)")
    result = speech_worker.audit_placement(raw.encode("utf-16-le"))
    assert result == dict(cudaGraphs=3, cudaNodes=36, cpuMetadataNodes=1)


@pytest.mark.parametrize("raw", [
    log_line("All nodes placed on [CPUExecutionProvider]. Number of nodes: 12"),
    gpu_blocks() + log_line("Node(s) placed on [CPUExecutionProvider]. Number of nodes: 1") + log_line("Conv (neural-layer)"),
    gpu_blocks() + log_line("Node(s) placed on [CPUExecutionProvider]. Number of nodes: 2") + log_line("Shape (length)"),
])
def test_speech_audit_refuses_neural_cpu_fallback_and_incomplete_evidence(placement_policy, raw):
    with pytest.raises(RuntimeError):
        speech_worker.audit_placement(raw.encode())


def test_worker_failure_reaches_caller_and_cleans_up(tmp_path, monkeypatch):
    process = SimpleNamespace(stdin=io.BytesIO(), stdout=io.BytesIO(b'{"error":"CPU fallback refused"}\n'), poll=lambda: 1)
    monkeypatch.setattr(speech_client.subprocess, "Popen", lambda *args, **kwargs: process)
    with pytest.raises(RuntimeError, match="CPU fallback refused"):
        speech_client.CudaSpeechRecognizer(tmp_path / "models", runtime_directory=tmp_path / "runtime")
    assert process.stdin.closed and process.stdout.closed
    assert not list((tmp_path / "runtime").glob("*.log"))


def test_missing_cuda_dependency_never_starts_cpu_speech(tmp_path, monkeypatch):
    monkeypatch.setattr(speech_runtime, "_handles", [])
    def missing(path):
        raise OSError("Synthetic missing CUDA dependency")
    monkeypatch.setattr(speech_runtime.os, "add_dll_directory", missing)
    monkeypatch.setenv("PATH", "synthetic")
    with pytest.raises(RuntimeError, match="CPU fallback is disabled"):
        speech_runtime.prepare_cuda(tmp_path)
