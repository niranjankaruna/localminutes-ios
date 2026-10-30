from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

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
        assert "Recommended" in window.model_choices.currentText()
        assert window.model_choices.count() == 2
        assert "27.3B parameters" in window.model_details.text() and "32,768" in window.model_details.text()
        index = next(i for i in range(window.model_choices.count()) if window.model_choices.itemData(i)["id"] == "gemma4-31b-it-q8_0")
        window.model_choices.setCurrentIndex(index)
        assert "30.7B parameters" in window.model_details.text()
        window.gpu.setChecked(False)
        assert "CPU inference" in window.model_details.text()
    finally:
        window.close(); store.close(); profile.close()
