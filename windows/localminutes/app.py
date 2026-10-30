from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import traceback
import wave

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QMessageBox

from . import __version__
from .audio import open_recognizer, recognize
from .files import Profile, atomic_write, copy_file, default_data_root, identifier, json_bytes, runtime_path
from .store import Store
from .ui import MainWindow


def synthetic_meeting(store):
    meeting = store.create("Product review")
    segments = [
        "Maya said the release date is Friday, provided the audio recovery tests pass.",
        "Leo will run the recovery tests on Thursday and report the results to Maya.",
        "The team agreed to keep microphone-only recording in the first Windows release.",
        "Syncing should copy updates without deleting meetings on the receiving device.",
    ]
    for sequence, text in enumerate(segments):
        store.insert("segment", dict(id=identifier(), meetingId=meeting["id"], sequence=sequence, startSample=sequence * 16000,
                                     endSample=(sequence + 1) * 16000, text=text, modelRevision="synthetic-fixture"))
    store.finish(meeting["id"], 64000)
    return store.get("meeting", meeting["id"])


def self_check(window, arguments):
    if window.store.meetings():
        raise ValueError("Self-check requires an empty isolated data directory.")
    runtime = runtime_path()
    version = subprocess.run([str(runtime / "llama-completion.exe"), "--version"], capture_output=True,
                             timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    text = (version.stdout + version.stderr).decode("utf-8", errors="replace")
    if version.returncode or "11900" not in text:
        raise ValueError("Pinned llama.cpp runtime failed its version check.")
    gpu = subprocess.run([str(runtime / "llama-completion.exe"), "--list-devices"], capture_output=True,
                         timeout=60, creationflags=subprocess.CREATE_NO_WINDOW)
    device_text = (gpu.stdout + gpu.stderr).decode("utf-8", errors="replace")
    window.resize(1440, 900); window.show(); QApplication.processEvents()
    report = dict(passed=True, version=__version__, python=sys.version.split()[0], frozen=bool(getattr(sys, "frozen", False)),
                  dataRoot=str(window.profile.root), runtimeRoot=str(runtime), summaryModels=len(window.models.summaries),
                  cudaBundled=(runtime / "ggml-cuda.dll").is_file(), cudaDeviceAvailable="CUDA0" in device_text,
                  nativeVersion=text.strip(), uiWidth=window.width(), uiHeight=window.height())
    if not report["cudaBundled"]:
        raise ValueError("CUDA runtime is missing from this build.")
    if arguments.smoke_model:
        model = next(model for model in window.models.summaries if model["id"] == "qwen2.5-0.5b-instruct-q4_k_m")
        copy_file(arguments.smoke_model, window.models.path(model))
        try:
            window.models.verify_summary(model); window.models.equip(model)
            meeting = synthetic_meeting(window.store)
            summary = window.intelligence.generate(meeting, None, lambda value: None, None)
            answer = window.intelligence.generate(meeting, "When will Leo run the recovery tests?", lambda value: None, None)
            if "Minutes of Meetings" not in summary["editedText"] or "Thursday" not in answer["editedText"]:
                raise ValueError("Synthetic inference did not produce the expected supported answer.")
            report["cudaInferencePassed"] = True
        finally:
            window.models.path(model).unlink(missing_ok=True)
    if arguments.speech_directory and arguments.speech_wav:
        with wave.open(str(arguments.speech_wav), "rb") as source:
            if (source.getframerate(), source.getnchannels(), source.getsampwidth()) != (16000, 1, 2):
                raise ValueError("Expected a synthetic 16 kHz mono speech fixture.")
            pcm = source.readframes(source.getnframes())
        transcript = recognize(open_recognizer(arguments.speech_directory), pcm)
        if "friday" not in transcript.casefold() or "thursday" not in transcript.casefold():
            raise ValueError("Synthetic speech recognition failed.")
        report["speechInferencePassed"] = True
    atomic_write(arguments.self_check, json.dumps(report, indent=2).encode("utf-8"))


def render_preview(window, destination: Path):
    if window.store.meetings():
        raise ValueError("Preview requires an empty isolated data directory.")
    destination.mkdir(parents=True, exist_ok=True)
    meeting = synthetic_meeting(window.store)
    window.store.save_note(meeting["id"], "Keep the first release focused. Check recovery behavior and the local transfer flow before release.", 0)
    now = datetime.now().timestamp()
    window.store.save_document(dict(id=identifier(), meetingId=meeting["id"], kind="summary", originalJson="{}", question=None,
        editedText="Overview\n\nThe team reviewed the meeting capture experience and the next release. The focus is reliable recording, useful summaries and simple transfers between devices.\n\nMinutes of Meetings\n\n• The release is planned for Friday, provided the audio recovery tests pass.\n\n• Leo will run the recovery tests on Thursday and share the results with Maya.\n\n• Microphone recording stays the focus of the first Windows release.\n\n• Sync copies meeting updates while keeping meetings that exist only on the receiving device.",
        editRevision=0, modelRevision="synthetic", promptVersion="preview", createdAt=now, modifiedAt=now))
    window.store.create("Design critique"); window.store.create("Weekly planning")
    window.reload(meeting["id"]); window.show(); QApplication.processEvents()
    for index, name in ((0, "meetings"), (1, "record"), (2, "sync"), (3, "settings")):
        window.switch_page(index); QApplication.processEvents(); window.grab().save(str(destination / (name + ".png")))
    window.dark.setChecked(True); window.switch_page(0); QApplication.processEvents(); window.grab().save(str(destination / "meetings-dark.png"))
    window.dark.setChecked(False); window.resize(1080, 720); QApplication.processEvents(); window.grab().save(str(destination / "meetings-small.png"))


def main(argv=None):
    parser = argparse.ArgumentParser(description="LocalMinutes for Windows")
    parser.add_argument("--data-directory", type=Path)
    parser.add_argument("--self-check", type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--smoke-model", type=Path)
    parser.add_argument("--speech-directory", type=Path)
    parser.add_argument("--speech-wav", type=Path)
    arguments = parser.parse_args(argv)
    diagnostic = arguments.self_check is not None or arguments.preview is not None
    if diagnostic and arguments.data_directory is None:
        parser.error("Diagnostic modes require an isolated --data-directory.")
    app = QApplication([sys.argv[0]])
    app.setApplicationName("LocalMinutes"); app.setApplicationVersion(__version__)
    profile = store = window = None
    try:
        profile = Profile(arguments.data_directory)
        # Python temporary work also stays inside the app's data directory.
        temporary = profile.root / "runtime" / "temporary"
        temporary.mkdir(parents=True, exist_ok=True)
        cuda_cache = profile.root / "runtime" / "cuda-cache"
        cuda_cache.mkdir(parents=True, exist_ok=True)
        os.environ["CUDA_CACHE_PATH"] = str(cuda_cache)
        import tempfile
        tempfile.tempdir = str(temporary)
        store = Store(profile.database)
        if diagnostic and store.meetings():
            raise ValueError("Diagnostic modes require an empty isolated library.")
        window = MainWindow(profile, store, preview=diagnostic)
        if diagnostic:
            window.setAttribute(Qt.WA_DontShowOnScreen)
        if arguments.self_check:
            self_check(window, arguments)
            return 0
        if arguments.preview:
            render_preview(window, arguments.preview)
            return 0
        window.show()
        return app.exec()
    except Exception as error:
        if arguments.self_check:
            atomic_write(arguments.self_check, json.dumps(dict(passed=False, error=str(error), traceback=traceback.format_exc()), indent=2).encode("utf-8"))
        elif arguments.preview:
            arguments.preview.mkdir(parents=True, exist_ok=True)
            (arguments.preview / "error.txt").write_text(traceback.format_exc(), encoding="utf-8")
        else:
            QMessageBox.critical(None, "LocalMinutes", "LocalMinutes could not open its data.\n\n" + str(error))
        return 1
    finally:
        if window:
            window.close()
        if store:
            store.close()
        if profile:
            profile.close()


if __name__ == "__main__":
    raise SystemExit(main())
