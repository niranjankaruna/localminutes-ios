from pathlib import Path
import json
import queue
import struct
import subprocess
import sys
import threading

from .files import check_cancel, identifier


def _read_messages(stream, messages):
    try:
        while line := stream.readline(1024 * 1024):
            if not line.endswith(b"\n"):
                raise ValueError("Invalid speech worker response.")
            messages.put(json.loads(line))
    except Exception as error:
        messages.put(dict(error=str(error)))
    finally:
        messages.put(dict(error="CUDA speech worker exited. CPU fallback was not used."))


class CudaSpeechRecognizer:
    def __init__(self, directory: Path, cancel=None, runtime_directory=None):
        self.process = None
        self.reader = None
        self.closed = False
        self.messages = queue.Queue()
        runtime = runtime_directory or directory.parent.parent / "runtime" / "speech"
        runtime.mkdir(parents=True, exist_ok=True)
        self.diagnostics = runtime / ("cuda-" + identifier() + ".log")
        command = [sys.executable]
        if not getattr(sys, "frozen", False):
            command.append(str(Path(__file__).resolve().parents[1] / "launch.py"))
        command += ["--speech-worker", "--model-directory", str(directory), "--runtime-directory", str(runtime), "--diagnostics", str(self.diagnostics)]
        try:
            with self.diagnostics.open("xb") as errors:
                self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
                                                creationflags=subprocess.CREATE_NO_WINDOW)
            self.reader = threading.Thread(target=_read_messages, args=(self.process.stdout, self.messages), daemon=True)
            self.reader.start()
            ready = self._receive(cancel)
            if ready.get("ready") is not True:
                raise RuntimeError("CUDA speech worker did not initialize.")
            self.placement = ready["placement"]
        except BaseException:
            self.close()
            raise

    def _receive(self, cancel=None):
        while True:
            check_cancel(cancel)
            try:
                result = self.messages.get(timeout=0.1)
                if "error" in result:
                    raise RuntimeError(result["error"])
                return result
            except queue.Empty:
                continue

    def transcribe(self, pcm: bytes):
        if self.closed:
            raise RuntimeError("CUDA speech worker is closed.")
        if not pcm:
            return ""
        self.process.stdin.write(struct.pack("<I", len(pcm)))
        self.process.stdin.write(pcm)
        self.process.stdin.flush()
        result = self._receive()
        if not isinstance(result.get("text"), str):
            raise RuntimeError("Invalid CUDA transcription response.")
        return result["text"]

    def close(self):
        if self.closed:
            return
        self.closed = True
        if self.process:
            if self.process.poll() is None:
                try:
                    self.process.stdin.write(struct.pack("<I", 0))
                    self.process.stdin.flush()
                    self.process.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    self.process.kill(); self.process.wait()
            self.process.stdin.close()
            if self.reader:
                self.reader.join(timeout=2)
            self.process.stdout.close()
        self.diagnostics.unlink(missing_ok=True)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def __del__(self):
        if hasattr(self, "closed"):
            try:
                self.close()
            except Exception:
                pass
