import threading
import time

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QMessageBox

from localminutes.files import Profile
from localminutes.store import Store
from localminutes.ui import MainWindow


def test_note_drafts_flush_on_selection_and_navigation(tmp_path):
    app = QApplication.instance() or QApplication([])
    profile = Profile(tmp_path / "profile")
    store = Store(profile.database)
    first, second = store.create("First"), store.create("Second")
    window = MainWindow(profile, store, preview=True)
    window.setAttribute(Qt.WA_DontShowOnScreen)
    try:
        window.reload(first["id"])
        window.notes.setPlainText("Unflushed note")
        for index in range(window.meeting_list.count()):
            item = window.meeting_list.item(index)
            if item.data(Qt.UserRole) == second["id"]:
                window.meeting_list.setCurrentItem(item)
                break
        assert store.get("note", first["id"])["text"] == "Unflushed note"
        window.notes.setPlainText("Second note")
        window.switch_page(3)
        assert store.get("note", second["id"])["text"] == "Second note"
        window.dark.setChecked(True)
        assert window.settings["dark"] is True
        assert window.models.selected is None
        assert window.model_groups.count() == 4
        assert "Recommended" in window.model_candidate_status.text()
        assert window.model_choices.count() == 2
        assert "27.3B stored parameters" in window.model_details.text() and "262,144" in window.model_details.text()
        assert "GPU only" in window.model_details.text() and "Thinking on" in window.model_details.text()
        window.model_groups.setCurrentIndex(window.model_groups.findData("hybrid"))
        index = next(i for i in range(window.model_choices.count()) if window.model_choices.itemData(i)["id"] == "gemma4-31b-it-q8_0")
        window.model_choices.setCurrentIndex(index)
        assert "30.7B stored parameters" in window.model_details.text()
        assert "offloading allowed" in window.model_details.text()
        for group_id in ("gpuLarge", "medium", "small"):
            window.model_groups.setCurrentIndex(window.model_groups.findData(group_id))
            assert window.model_choices.count() == 2 and "CPU fallback disabled" in window.model_details.text()
        assert not hasattr(window, "gpu")
    finally:
        window.close(); store.close(); profile.close()


@pytest.fixture
def settings_window(tmp_path):
    app = QApplication.instance() or QApplication([])
    profile = Profile(tmp_path / "profile")
    store = Store(profile.database)
    window = MainWindow(profile, store, preview=True)
    window.setAttribute(Qt.WA_DontShowOnScreen)
    window.switch_page(3)
    try:
        yield window
    finally:
        window.cancel.set()
        wait_until(lambda: not window.busy)
        window.close(); store.close(); profile.close()


def wait_until(condition, timeout=5):
    deadline = time.monotonic() + timeout
    while not condition() and time.monotonic() < deadline:
        QApplication.processEvents()
        time.sleep(0.01)
    assert condition(), "UI operation did not finish"


def install_fixture_model(window, monkeypatch):
    """Use tiny files to exercise UI state without downloading real weights."""
    monkeypatch.setattr(window.models, "present", lambda model: window.models.path(model).is_file())
    model = window.model_choices.currentData()
    path = window.models.path(model)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"test")
    window.update_models()
    return model, path


def test_settings_exposes_tasks_and_hides_technical_details(settings_window):
    window = settings_window
    assert [window.settings_tabs.tabText(i).replace("&&", "&") for i in range(window.settings_tabs.count())] == [
        "Models", "Library & storage", "Appearance"]
    assert window.model_groups.accessibleName() == "Model size"
    assert window.model_choices.accessibleName() == "Model"
    assert window.model_action.text().startswith("Download model")
    assert "Not downloaded" in window.model_candidate_status.text()
    assert window.model_remove.isHidden()
    assert window.model_technical.isHidden()
    window.model_technical_toggle.click()
    assert not window.model_technical.isHidden()
    assert "262,144" in window.model_details.text()
    window.model_technical_toggle.click()
    assert window.model_technical.isHidden()


def test_model_browsing_never_changes_active_selection(settings_window, monkeypatch):
    window = settings_window
    model, path = install_fixture_model(window, monkeypatch)
    assert window.model_action.text() == "Use model"
    assert not window.model_remove.isHidden()
    window.model_action.click()
    assert window.models.selected_id == model["id"]
    assert window.model_action.text() == "In use"
    assert not window.model_action.isEnabled()
    window.model_groups.setCurrentIndex(window.model_groups.findData("small"))
    window.model_choices.setCurrentIndex(1)
    assert window.models.selected_id == model["id"]
    assert window.models.name(model) in window.model_status.text()
    assert window.model_action.text().startswith("Download model")
    window.model_groups.setCurrentIndex(window.model_groups.findData(model["group"]))
    assert window.model_choices.currentData()["id"] == model["id"]
    assert window.model_action.text() == "In use"
    path.unlink()
    window.update_models()
    assert "needs downloading" in window.model_status.text()
    assert window.model_action.text().startswith("Download model")
    assert window.model_action.isEnabled()


@pytest.mark.parametrize("recording", [False, True])
def test_settings_mutations_blocked_during_work_or_recording(settings_window, monkeypatch, recording):
    window = settings_window
    model, path = install_fixture_model(window, monkeypatch)
    def unexpected(*args, **kwargs):
        pytest.fail("A blocked settings action attempted work or confirmation")
    monkeypatch.setattr(window, "run_work", unexpected)
    monkeypatch.setattr(QMessageBox, "question", unexpected)
    if recording:
        window.recorder.worker = object()
    else:
        window.busy = True
    try:
        window.update_settings_controls()
        for control in (window.model_action, window.model_remove, window.model_repair,
                        window.speech_download, window.speech_remove, window.library_import, window.library_export):
            assert not control.isEnabled()
        assert not window.settings_availability.isHidden()
        window.equip_model(); window.download_model(); window.download_speech()
        window.remove_model(); window.remove_speech()
        assert window.models.selected_id is None
        assert path.exists()
    finally:
        window.busy = False
        window.recorder.worker = None
        window.update_settings_controls()
    assert window.model_action.isEnabled()
    assert window.settings_availability.isHidden()


def test_removing_active_model_requires_confirmation_and_preserves_library(settings_window, monkeypatch):
    window = settings_window
    meeting = window.store.create("Keep this meeting")
    model, path = install_fixture_model(window, monkeypatch)
    window.model_action.click()
    questions = []
    def decline(*args):
        questions.append(args)
        return QMessageBox.No
    monkeypatch.setattr(QMessageBox, "question", decline)
    window.remove_model()
    assert path.exists()
    assert window.models.selected_id == model["id"]
    assert "in use" in questions[0][2]
    assert questions[0][-1] == QMessageBox.No
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.Yes)
    window.settings_feedback.show()
    window.remove_model()
    wait_until(lambda: not window.busy)
    assert window.settings_feedback.isHidden()
    assert not path.exists()
    assert window.models.selected_id is None
    assert window.store.get("meeting", meeting["id"])["title"] == "Keep this meeting"
    assert window.model_action.text().startswith("Download model")


def test_incomplete_speech_download_can_be_removed(settings_window, monkeypatch):
    window = settings_window
    directory = window.models.speech_directory
    directory.mkdir(parents=True, exist_ok=True)
    partial = directory / "encoder.onnx.partial"
    partial.write_bytes(b"unfinished")
    window.update_models()
    assert not window.models.speech_present
    assert not window.speech_remove.isHidden()
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.No)
    window.remove_speech()
    assert partial.exists()
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.Yes)
    window.remove_speech()
    wait_until(lambda: not window.busy)
    assert not partial.exists()
    assert window.speech_remove.isHidden()


@pytest.mark.parametrize("outcome", ["success", "failure", "cancel"])
def test_download_feedback_returns_to_usable_state(settings_window, monkeypatch, outcome):
    window = settings_window
    model = window.model_choices.currentData()
    monkeypatch.setattr(window.models, "present", lambda candidate: window.models.path(candidate).is_file())
    release = threading.Event()
    def download(candidate, progress, cancel):
        progress("Downloading test model")
        assert release.wait(3), "Test download was not released"
        if cancel.is_set():
            raise InterruptedError("Operation cancelled")
        if outcome == "failure":
            raise OSError("Test connection failed")
        path = window.models.path(candidate)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"test")
    monkeypatch.setattr(window.models, "download_summary", download)
    warnings = []
    monkeypatch.setattr(QMessageBox, "warning", lambda *args: warnings.append(args[2]))
    window.model_action.click()
    assert window.busy
    assert not window.settings_feedback.isHidden()
    assert window.settings_feedback_title.text() == window.models.name(model)
    assert not window.model_action.isEnabled()
    if outcome == "cancel":
        window.settings_cancel.click()
        assert window.cancel.is_set()
        assert "start again" in window.settings_feedback_text.text()
    release.set()
    wait_until(lambda: not window.busy)
    assert window.settings_operation is None
    assert window.settings_progress.isHidden()
    assert window.settings_cancel.isHidden()
    assert window.model_action.isEnabled()
    assert window.models.selected_id is None
    if outcome == "success":
        assert window.model_action.text() == "Use model"
        assert "Download complete" in window.settings_feedback_text.text()
    elif outcome == "failure":
        assert warnings == ["Test connection failed"]
        assert window.settings_feedback_text.text() == "Test connection failed"
        assert window.model_action.text().startswith("Download model")
    else:
        assert not warnings
        assert "Operation cancelled" in window.settings_feedback_text.text()
