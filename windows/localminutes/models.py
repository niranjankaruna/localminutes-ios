from __future__ import annotations

import os
from pathlib import Path
import shutil
import threading
import time
import urllib.request

from .files import atomic_write, check_cancel, digest, json_bytes, read_json, safe_path


SPEECH_REVISION = "2bda32ec70b097a55adaa07d9a7173915b43cc78"
SPEECH_REPOSITORY = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
SPEECH_FILES = [
    ("encoder.int8.onnx", 652184281, "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247"),
    ("decoder.int8.onnx", 11845275, "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e"),
    ("joiner.int8.onnx", 6355277, "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3"),
    ("tokens.txt", 93939, "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d"),
]


class Models:
    speech_revision = SPEECH_REVISION

    def __init__(self, profile):
        self.profile = profile
        catalog = read_json(Path(__file__).parent / "resources" / "SummaryCatalog.json")
        self.summaries = [model for family in catalog["families"] for model in family["variants"]]
        self.selection_path = profile.root / "model-selection.json"
        self.selected_id = read_json(self.selection_path, 4096) if self.selection_path.exists() else None
        self.speech_directory = safe_path(profile.models, "parakeet-v3-onnx")
        self.lock = threading.Lock()

    @property
    def selected(self):
        return next((model for model in self.summaries if model["id"] == self.selected_id), None)

    def path(self, model):
        return safe_path(self.profile.models, model["id"] + "/" + model["fileName"])

    def present(self, model):
        path = self.path(model)
        return path.is_file() and path.stat().st_size == model["byteCount"]

    @property
    def speech_present(self):
        return all((self.speech_directory / name).is_file() and (self.speech_directory / name).stat().st_size == size for name, size, _ in SPEECH_FILES)

    def equip(self, model):
        if not self.present(model):
            raise ValueError("Download this model before equipping it.")
        atomic_write(self.selection_path, json_bytes(model["id"]))
        self.selected_id = model["id"]

    @staticmethod
    def verify(path, size, sha, cancel=None):
        if not path.is_file() or path.stat().st_size != size or digest(path, cancel) != sha:
            raise ValueError("Model is missing or failed verification. Download it again in Settings.")

    def verify_speech(self, cancel=None):
        for name, size, sha in SPEECH_FILES:
            self.verify(safe_path(self.speech_directory, name), size, sha, cancel)

    def verify_summary(self, model, cancel=None):
        self.verify(self.path(model), model["byteCount"], model["sha256"], cancel)

    def download_summary(self, model, progress, cancel):
        with self.lock:
            self._download(model["repository"], model["revision"], self.path(model), model["byteCount"], model["sha256"], progress, cancel)

    def download_speech(self, progress, cancel):
        with self.lock:
            for name, size, sha in SPEECH_FILES:
                self._download(SPEECH_REPOSITORY, SPEECH_REVISION, safe_path(self.speech_directory, name), size, sha, progress, cancel)

    def _download(self, repository, revision, target, size, sha, progress, cancel):
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            try:
                self.verify(target, size, sha, cancel)
                progress(target.name + " verified")
                return
            except ValueError:
                pass
        if shutil.disk_usage(target.parent).free < size + 100000000:
            raise OSError("Not enough free storage to download this model.")
        partial = safe_path(target.parent, target.name + ".partial")
        url = f"https://huggingface.co/{repository}/resolve/{revision}/{target.name}"
        request = urllib.request.Request(url, headers={"User-Agent": "LocalMinutes/0.2"})
        try:
            partial.unlink(missing_ok=True)
            with urllib.request.urlopen(request, timeout=30) as response, partial.open("xb") as stream:
                if not response.url.startswith("https://") or (response.headers.get("Content-Length") is not None and int(response.headers["Content-Length"]) != size):
                    raise ValueError("Unexpected model download response.")
                total, last = 0, 0.0
                while chunk := response.read(131072):
                    check_cancel(cancel)
                    total += len(chunk)
                    if total > size:
                        raise ValueError("Model download exceeds its expected size.")
                    stream.write(chunk)
                    if time.monotonic() - last > 0.1:
                        progress(f"Downloading {target.name}: {total / 1000000:,.0f} / {size / 1000000:,.0f} MB")
                        last = time.monotonic()
                stream.flush()
                os.fsync(stream.fileno())
            progress("Verifying " + target.name)
            self.verify(partial, size, sha, cancel)
            os.replace(partial, target)
        finally:
            partial.unlink(missing_ok=True)

    def remove_summary(self, model):
        with self.lock:
            target = self.path(model)
            target.unlink(missing_ok=True)
            safe_path(target.parent, target.name + ".partial").unlink(missing_ok=True)
            if self.selected_id == model["id"]:
                atomic_write(self.selection_path, b"null")
                self.selected_id = None

    def remove_speech(self):
        with self.lock:
            for name, _, _ in SPEECH_FILES:
                for filename in (name, name + ".partial"):
                    safe_path(self.speech_directory, filename).unlink(missing_ok=True)
