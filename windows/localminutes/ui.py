from __future__ import annotations

import base64
from datetime import datetime
from pathlib import Path
import threading
import time

import qrcode
from PySide6.QtCore import QObject, QRunnable, QThreadPool, Qt, QTimer, Signal, QSize
from PySide6.QtGui import QColor, QFont, QIcon, QImage, QPainter, QPixmap, QDesktopServices
from PySide6.QtCore import QUrl
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QDialog, QFileDialog, QFrame, QHBoxLayout, QInputDialog, QLabel,
    QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QMenu, QMessageBox, QPlainTextEdit, QProgressBar, QPushButton, QScrollArea,
    QSizePolicy, QSplitter, QStackedWidget, QStyledItemDelegate, QStyle, QTabWidget, QTextEdit, QVBoxLayout, QWidget)

from . import exchange, library
from .audio import Playback, Recorder, reconcile_recordings
from .files import atomic_write, identifier, json_bytes, read_json, runtime_path, assets
from .intelligence import Intelligence
from .models import Models, SPEECH_FILES
from .sync import SyncHost, local_addresses
from .theme import apply_theme


def label(text, name=None, wrap=False):
    value = QLabel(text)
    if name:
        value.setObjectName(name)
    value.setWordWrap(wrap)
    return value


def panel(spacing=16, margin=0):
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setContentsMargins(margin, margin, margin, margin)
    layout.setSpacing(spacing)
    return widget, layout


def row(*widgets):
    widget = QWidget()
    layout = QHBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(10)
    for item in widgets:
        if item is None:
            layout.addStretch()
        else:
            layout.addWidget(item)
    return widget


def button(text, action, name=None):
    control = QPushButton(text)
    if name:
        control.setObjectName(name)
    control.clicked.connect(action)
    control.setCursor(Qt.PointingHandCursor)
    return control


class Signals(QObject):
    progress = Signal(str)
    result = Signal(object)
    failed = Signal(str)
    finished = Signal()


class Work(QRunnable):
    def __init__(self, action, cancel):
        super().__init__()
        self.action, self.cancel, self.signals = action, cancel, Signals()

    def run(self):
        try:
            self.signals.result.emit(self.action(self.signals.progress.emit, self.cancel))
        except Exception as error:
            self.signals.failed.emit(str(error))
        finally:
            self.signals.finished.emit()


class Bridge(QObject):
    message = Signal(str)
    transcript = Signal(str)
    prepare_import = Signal(object)
    import_finished = Signal()
    imported = Signal()


class MeetingDelegate(QStyledItemDelegate):
    def sizeHint(self, option, index):
        return QSize(260, 76)

    def paint(self, painter, option, index):
        painter.save()
        rect = option.rect.adjusted(8, 3, -8, -3)
        palette = option.palette
        if option.state & QStyle.State_Selected:
            painter.setPen(Qt.NoPen); painter.setBrush(palette.highlight()); painter.drawRoundedRect(rect, 10, 10)
        elif option.state & QStyle.State_MouseOver:
            painter.setPen(Qt.NoPen); painter.setBrush(palette.button()); painter.drawRoundedRect(rect, 10, 10)
        title, metadata = index.data(Qt.DisplayRole).split("\n", 1)
        font = QFont(option.font); font.setPixelSize(14); font.setWeight(QFont.DemiBold)
        painter.setFont(font); painter.setPen(palette.text().color())
        text_rect = rect.adjusted(15, 12, -12, -30)
        painter.drawText(text_rect, Qt.AlignLeft | Qt.AlignVCenter, painter.fontMetrics().elidedText(title, Qt.ElideRight, text_rect.width()))
        font.setPixelSize(12); font.setWeight(QFont.Normal); painter.setFont(font); painter.setPen(palette.placeholderText().color())
        painter.drawText(rect.adjusted(15, 35, -12, -8), Qt.AlignLeft | Qt.AlignVCenter, metadata)
        painter.restore()


class MainWindow(QMainWindow):
    def __init__(self, profile, store, *, preview=False):
        super().__init__()
        self.profile, self.store, self.preview = profile, store, preview
        exchange.recover(profile, store); library.recover_deletions(profile, store); reconcile_recordings(profile, store)
        self.models = Models(profile)
        self.intelligence = Intelligence(profile, store, self.models)
        self.bridge = Bridge()
        self.recorder = Recorder(profile, store, self.models, self.bridge.transcript.emit)
        self.playback = Playback()
        self.busy = self.loading = self.close_pending = False
        self.selected = self.summary = None
        self.note_revision = 0
        self.saved_note = self.saved_summary = ""
        self.cancel = threading.Event()
        self.work = None
        self.pair_dialog = None
        self.settings_path = profile.root / "settings.json"
        self.settings = read_json(self.settings_path, 4096) if self.settings_path.exists() else {}
        apply_theme(QApplication.instance(), self.settings.get("dark", False))
        self.sync = SyncHost(profile, store, lambda: not self.busy and not self.recorder.active,
                             self.bridge.message.emit, self.request_import, self.bridge.import_finished.emit, self.bridge.imported.emit)
        self.setWindowTitle("LocalMinutes")
        self.resize(1440, 900); self.setMinimumSize(1080, 720)
        mark = Path(__file__).parent / "resources" / "mark.png"
        self.setWindowIcon(QIcon(str(mark)))
        self._build(mark)
        self.bridge.message.connect(self.show_status)
        self.bridge.transcript.connect(self.live.appendPlainText)
        self.bridge.prepare_import.connect(self.begin_import)
        self.bridge.import_finished.connect(self.end_import)
        self.bridge.imported.connect(lambda: self.reload(self.selected["id"] if self.selected else None))
        self.notes_timer = QTimer(self); self.notes_timer.setSingleShot(True); self.notes_timer.setInterval(500)
        self.notes_timer.timeout.connect(lambda: self.invoke(self.flush))
        self.clock = QTimer(self); self.clock.setInterval(250); self.clock.timeout.connect(self.update_recording); self.clock.start()
        self.reload()
        self.update_models()
        if not preview:
            QTimer.singleShot(0, lambda: self.invoke(self.sync.start))

    def _build(self, mark):
        root, outer = panel(0)
        body = QWidget(); layout = QHBoxLayout(body); layout.setContentsMargins(0, 0, 0, 0); layout.setSpacing(0)
        sidebar, nav = panel(7, 18); sidebar.setObjectName("sidebar"); sidebar.setFixedWidth(218)
        image = QLabel(); image.setPixmap(QPixmap(str(mark)).scaled(34, 34, Qt.KeepAspectRatio, Qt.SmoothTransformation))
        nav.addWidget(row(image, label("LocalMinutes", "brand"))); nav.addSpacing(28)
        self.pages = QStackedWidget()
        self.navigation = []
        for index, title in enumerate(("Meetings", "Record", "Sync", "Settings")):
            control = button(title, lambda checked=False, i=index: self.switch_page(i), "navigation")
            control.setCheckable(True); control.setMinimumHeight(43); nav.addWidget(control); self.navigation.append(control)
        nav.addStretch()
        nav.addWidget(label("On this device", "muted"))
        nav.addWidget(label(self.profile.identity["deviceName"]))
        nav.addWidget(label("Private by default", "muted"))
        self.navigation[0].setChecked(True)
        layout.addWidget(sidebar); layout.addWidget(self.pages, 1)
        self.pages.addWidget(self._meetings_page())
        self.pages.addWidget(self._record_page())
        self.pages.addWidget(self._sync_page())
        self.pages.addWidget(self._settings_page())
        outer.addWidget(body, 1)
        footer, footer_layout = panel(0)
        footer_layout.setContentsMargins(22, 9, 22, 9)
        self.status = label("Saved on your device", "muted")
        self.status.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        self.cancel_button = button("Cancel", self.cancel_current, "quiet"); self.cancel_button.hide()
        footer_layout.addWidget(row(self.status, self.cancel_button))
        self.progress = QProgressBar(); self.progress.setTextVisible(False); self.progress.setFixedHeight(3); self.progress.hide()
        outer.addWidget(self.progress); outer.addWidget(footer)
        self.setCentralWidget(root)

    def _meetings_page(self):
        splitter = QSplitter()
        column, left = panel(12, 16); column.setObjectName("meetingColumn"); column.setMinimumWidth(265); column.setMaximumWidth(420)
        left.addWidget(row(label("Meetings", "section"), None, button("+", self.new_meeting)))
        self.search = QLineEdit(); self.search.setPlaceholderText("Search meetings"); self.search.textChanged.connect(lambda: self.reload(self.selected["id"] if self.selected else None))
        left.addWidget(self.search)
        self.meeting_list = QListWidget(); self.meeting_list.setMouseTracking(True); self.meeting_list.setItemDelegate(MeetingDelegate(self.meeting_list))
        self.meeting_list.currentItemChanged.connect(self.meeting_changed); left.addWidget(self.meeting_list, 1)
        self.meeting_count = label("No meetings yet", "muted"); left.addWidget(self.meeting_count)
        content, right = panel(20, 28)
        right.addWidget(row(label("Your library", "muted"), None, button("Sync", lambda: self.switch_page(2)), button("Record a meeting", lambda: self.switch_page(1), "primary")))
        self.detail_stack = QStackedWidget(); right.addWidget(self.detail_stack, 1)
        empty, empty_layout = panel(12, 40)
        empty_layout.addStretch(); empty_layout.addWidget(label("A little more clarity.", "title"))
        empty_layout.addWidget(label("Record a meeting, or start with a note.\nYour words and ideas stay on your devices.", "muted", True))
        empty_layout.addWidget(row(button("New meeting", self.new_meeting, "primary"), None)); empty_layout.addStretch()
        self.detail_stack.addWidget(empty)
        self.detail, detail = panel(12)
        self.title = label("", "title", True); self.metadata = label("", "muted")
        detail.addWidget(row(self.title, None, button("•••", self.meeting_menu)))
        detail.addWidget(self.metadata); detail.addSpacing(6)
        self.tabs = QTabWidget(); self.tabs.currentChanged.connect(lambda: self.invoke(self.flush) if not self.loading else None)
        summary_page, summary_layout = panel(12, 10)
        summary_layout.addWidget(row(button("Generate summary", lambda: self.generate(None), "primary"), button("Sources", self.show_summary_sources), None, button("Save edit", lambda: self.invoke(self.flush), "quiet")))
        self.summary_text = QPlainTextEdit(); self.summary_text.setPlaceholderText("A clear overview and meeting minutes will appear here.")
        summary_layout.addWidget(self.summary_text, 1); self.tabs.addTab(summary_page, "Summary")
        transcript_page, transcript_layout = panel(12, 10)
        self.transcript_search = QLineEdit(); self.transcript_search.setPlaceholderText("Find in transcript"); self.transcript_search.textChanged.connect(self.refresh_transcript)
        transcript_layout.addWidget(self.transcript_search)
        self.transcript_list = QListWidget(); self.transcript_list.setWordWrap(True); self.transcript_list.itemDoubleClicked.connect(self.seek_transcript)
        transcript_layout.addWidget(self.transcript_list, 1); self.tabs.addTab(transcript_page, "Transcript")
        self.notes = QPlainTextEdit(); self.notes.setPlaceholderText("What matters to you? Add notes here…"); self.notes.textChanged.connect(self.notes_changed)
        self.tabs.addTab(self.notes, "Notes")
        ask_page, ask_layout = panel(12, 10)
        self.question = QLineEdit(); self.question.setPlaceholderText("Ask something about this meeting…"); self.question.returnPressed.connect(self.ask)
        ask_layout.addWidget(row(self.question, button("Ask", self.ask, "primary")))
        self.answers = QListWidget(); self.answers.setWordWrap(True); self.answers.itemDoubleClicked.connect(self.open_answer)
        ask_layout.addWidget(self.answers, 1); ask_layout.addWidget(label("Answers quote the meeting and link back to their sources.", "muted", True))
        self.tabs.addTab(ask_page, "Ask")
        detail.addWidget(self.tabs, 1)
        self.audio_caption = label("Original recording", "muted")
        detail.addWidget(row(button("Play", lambda: self.play_audio(0)), button("Stop", self.playback.stop), self.audio_caption, None))
        self.detail_stack.addWidget(self.detail)
        splitter.addWidget(column); splitter.addWidget(content); splitter.setSizes([305, 900]); splitter.setChildrenCollapsible(False)
        return splitter

    def page_header(self, title, detail):
        widget, layout = panel(14, 36)
        layout.addWidget(label(title, "title")); layout.addWidget(label(detail, "muted", True)); layout.addSpacing(14)
        return widget, layout

    def _record_page(self):
        widget, layout = self.page_header("Make room for the conversation.", "Record your microphone. Keep the original audio, and turn the conversation into a transcript on this device.")
        self.microphones = QComboBox()
        try:
            for index, name in Recorder.microphones():
                self.microphones.addItem(name, index)
        except Exception:
            pass
        if not self.microphones.count():
            self.microphones.addItem("No microphone available", None)
        layout.addWidget(row(label("Microphone"), self.microphones, None))
        self.timer = label("00:00:00", "timer"); self.timer.setAlignment(Qt.AlignCenter); layout.addWidget(self.timer)
        self.record_state = label("Ready when you are", "muted"); self.record_state.setAlignment(Qt.AlignCenter); layout.addWidget(self.record_state)
        self.record_button = button("Start recording", self.toggle_recording, "record")
        layout.addWidget(row(None, self.record_button, None)); layout.addSpacing(18)
        layout.addWidget(row(label("Live transcript", "section"), None, button("Open meeting", self.open_recording, "quiet")))
        self.live = QPlainTextEdit(); self.live.setReadOnly(True); self.live.setPlaceholderText("Your transcript will appear as you speak."); layout.addWidget(self.live, 1)
        return widget

    def _sync_page(self):
        widget, layout = self.page_header("Together, without the cloud.", "Copy your saved meetings between this PC and your iPhone over the same Wi-Fi.")
        group, group_layout = panel(20, 26); group.setObjectName("readingSurface")
        group_layout.addWidget(label("This Windows PC", "section"))
        group_layout.addWidget(label(self.profile.identity["deviceName"]))
        self.sync_status = label("Pair your iPhone to get started.", "muted", True); group_layout.addWidget(self.sync_status)
        self.addresses = QComboBox(); self.addresses.addItems(local_addresses()); group_layout.addWidget(row(label("Local address"), self.addresses, None))
        group_layout.addWidget(row(button("Pair an iPhone", self.pair, "primary"), button("Sync to iPhone", self.send), None))
        group_layout.addWidget(row(button("Cancel PC send", lambda: self.invoke(self.sync.cancel_send), "quiet"), button("Forget pairing", self.forget, "quiet"), None))
        layout.addWidget(group)
        layout.addSpacing(12)
        layout.addWidget(label("Open Sync on both devices", "section"))
        layout.addWidget(label("Keep the iPhone Sync screen open and the phone unlocked. Press Sync on the device whose saved version you want to send.", "muted", True))
        layout.addWidget(label("The sender replaces matching edits. Meetings only on the receiving device stay there. Deletions and downloaded models are never copied.", "muted", True))
        identity = label("Device ID  " + self.profile.identity["replicaId"] + "\nInstance  " + self.profile.run_id, "muted", True)
        identity.setTextInteractionFlags(Qt.TextSelectableByMouse); layout.addStretch(); layout.addWidget(identity)
        return widget

    def _settings_page(self):
        widget, layout = self.page_header("Settings", "Make this PC ready for your next meeting.")
        self.settings_tabs = QTabWidget(); self.settings_tabs.setObjectName("settingsTabs")
        layout.addWidget(self.settings_tabs, 1)

        def settings_tab(title):
            scroll = QScrollArea(); scroll.setWidgetResizable(True)
            content, items = panel(20, 22)
            items.setAlignment(Qt.AlignTop)
            scroll.setWidget(content)
            self.settings_tabs.addTab(scroll, title.replace("&", "&&"))
            return items

        models_layout = settings_tab("Models")
        models_layout.addWidget(label("Download once. Use on this PC.", "section"))
        models_layout.addWidget(label("Speech turns audio into a transcript. A second model writes summaries and answers. Both run locally and require a compatible NVIDIA graphics card.", "muted", True))

        speech, speech_layout = panel(10, 20); speech.setObjectName("settingsSection")
        speech_layout.addWidget(label("Speech transcription", "section"))
        self.speech_status = label("", "muted", True)
        speech_layout.addWidget(self.speech_status)
        self.speech_download = button("Download speech model · 2.55 GB", self.download_speech, "primary")
        self.speech_remove = button("Remove…", self.remove_speech, "quiet")
        self.speech_remove.setAccessibleName("Remove speech model")
        speech_layout.addWidget(row(self.speech_download, self.speech_remove, None))
        models_layout.addWidget(speech)

        model_group, group = panel(12, 20); model_group.setObjectName("settingsSection")
        group.addWidget(label("Summaries & answers", "section"))
        self.model_status = label("", "settingsStatus", True); group.addWidget(self.model_status)
        selectors = QWidget(); fields = QHBoxLayout(selectors); fields.setContentsMargins(0, 0, 0, 0); fields.setSpacing(18)
        self.model_groups = QComboBox()
        group_titles = {"hybrid": "Highest precision · GPU + RAM", "gpuLarge": "Large · GPU only", "medium": "Medium · GPU only", "small": "Small · GPU only"}
        for item in self.models.groups:
            self.model_groups.addItem(group_titles.get(item["id"], item["title"]), item["id"])
        initial = self.models.selected or next(model for model in self.models.summaries if model["id"] == self.models.recommended_id)
        self.model_groups.setCurrentIndex(self.model_groups.findData(initial["group"]))
        self.model_choices = QComboBox()
        for title, control, stretch in (("Model &size", self.model_groups, 2), ("&Model", self.model_choices, 3)):
            field, field_layout = panel(7)
            caption = label(title); caption.setBuddy(control)
            control.setAccessibleName(title.replace("&", ""))
            control.setObjectName("settingsCombo")
            control.setMinimumContentsLength(12)
            control.setSizeAdjustPolicy(QComboBox.AdjustToMinimumContentsLengthWithIcon)
            field_layout.addWidget(caption); field_layout.addWidget(control); fields.addWidget(field, stretch)
        group.addWidget(selectors)
        self.model_guidance = label("", "muted", True); group.addWidget(self.model_guidance)
        self.model_candidate_status = label("", "settingsModelState", True); group.addWidget(self.model_candidate_status)
        self.model_action = button("Download model", self.activate_model, "primary")
        self.model_remove = button("Remove…", self.remove_model, "quiet")
        self.model_remove.setAccessibleName("Remove selected summary model")
        group.addWidget(row(self.model_action, self.model_remove, None))
        self.model_technical_toggle = button("Show technical details", self.toggle_model_details, "quiet")
        self.model_technical_toggle.setCheckable(True)
        group.addWidget(row(self.model_technical_toggle, None))
        self.model_technical, technical = panel(10)
        self.model_details = label("", "muted", True); self.model_details.setTextInteractionFlags(Qt.TextSelectableByMouse)
        technical.addWidget(self.model_details)
        self.model_repair = button("Download again", self.download_model)
        self.model_repair.setToolTip("Replace the model files if loading or verification fails.")
        technical.addWidget(row(self.model_repair, None))
        self.model_technical.hide(); group.addWidget(self.model_technical)
        self.model_choices.currentIndexChanged.connect(lambda _: self.update_model_details())
        self.model_groups.currentIndexChanged.connect(lambda _: self.populate_model_choices())
        models_layout.addWidget(model_group)

        storage = settings_tab("Library & storage")
        storage.addWidget(label("Your meeting library", "section"))
        storage.addWidget(label("Keep a copy of your meetings or bring in a library from another device. Exports include recordings, transcripts, notes and saved answers, but not downloaded models or pairing details.", "muted", True))
        self.library_export = button("Export library…", self.export_library)
        self.library_import = button("Import library…", self.import_library)
        storage.addWidget(row(self.library_export, self.library_import, None))
        storage.addWidget(label("Importing replaces matching edits and keeps meetings that exist only on this PC. Exported folders contain private meeting data and are not encrypted by the app.", "muted", True))
        storage.addSpacing(12); storage.addWidget(label("Saved on this PC", "section"))
        data_path = QLineEdit(str(self.profile.root)); data_path.setReadOnly(True); data_path.setAccessibleName("Application data folder")
        storage.addWidget(data_path)
        storage.addWidget(row(button("Open data folder", lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.profile.root)))), None))
        storage.addWidget(label("Meetings, models and preferences stay here when you replace the application.", "muted", True))

        prefs = settings_tab("Appearance")
        prefs.addWidget(label("Appearance", "section"))
        prefs.addWidget(label("Choose a comfortable look for this PC. Changes are saved automatically.", "muted", True))
        self.dark = QCheckBox("Dark appearance"); self.dark.setChecked(self.settings.get("dark", False)); self.dark.toggled.connect(self.save_settings); prefs.addWidget(self.dark)
        prefs.addSpacing(18); prefs.addWidget(label("About LocalMinutes", "section"))
        prefs.addWidget(label("Local recording, transcription and meeting notes. No account required.", "muted", True))
        prefs.addWidget(row(button("Open-source licenses", self.show_licenses, "quiet"), None))

        self.settings_operation = None
        self.settings_feedback, feedback = panel(8, 14); self.settings_feedback.setObjectName("settingsFeedback")
        self.settings_feedback_title = label("", "settingsModelState")
        self.settings_feedback_text = label("", "muted", True)
        self.settings_cancel = button("Cancel download", self.cancel_current)
        feedback.addWidget(row(self.settings_feedback_title, None, self.settings_cancel))
        feedback.addWidget(self.settings_feedback_text)
        self.settings_progress = QProgressBar(); self.settings_progress.setRange(0, 0); self.settings_progress.setTextVisible(False)
        feedback.addWidget(self.settings_progress)
        self.settings_feedback.hide(); layout.addWidget(self.settings_feedback)
        self.settings_availability = label("", "muted", True); self.settings_availability.hide(); layout.addWidget(self.settings_availability)
        self.populate_model_choices()
        return widget

    def toggle_model_details(self, checked):
        self.model_technical.setVisible(checked)
        self.model_technical_toggle.setText("Hide technical details" if checked else "Show technical details")

    def invoke(self, action):
        try:
            return action()
        except Exception as error:
            self.show_error(str(error))
            return None

    def show_status(self, text):
        self.status.setText(text); self.status.setToolTip(text)
        self.sync_status.setText(text if "iPhone" in text or "Sync" in text or "network" in text or "library" in text else self.sync_status.text())
        if self.sync.connected_phone and self.pair_dialog:
            self.pair_dialog.close(); self.pair_dialog = None

    def show_work_status(self, text):
        self.show_status(text)
        if self.settings_operation:
            self.settings_feedback_text.setText(text)

    def show_error(self, text):
        self.show_work_status(text)
        if not text.startswith("Operation cancelled"):
            QMessageBox.warning(self, "LocalMinutes", text)

    def run_work(self, action, result=None):
        if self.busy:
            self.show_status("Wait for the current operation to finish."); return False
        try:
            self.flush()
        except Exception as error:
            self.show_error(str(error)); return False
        self.busy = True; self.detail.setEnabled(False); self.meeting_list.setEnabled(False); self.search.setEnabled(False)
        self.settings_feedback.hide()
        self.update_settings_controls()
        self.cancel = threading.Event(); self.cancel_button.show(); self.progress.setRange(0, 0); self.progress.show()
        work = Work(action, self.cancel); self.work = work
        work.signals.progress.connect(self.show_work_status)
        if result:
            work.signals.result.connect(result)
        work.signals.failed.connect(self.show_error)
        work.signals.finished.connect(self.work_finished)
        QThreadPool.globalInstance().start(work)
        return True

    def work_finished(self):
        self.busy = False; self.work = None; self.detail.setEnabled(True); self.meeting_list.setEnabled(True); self.search.setEnabled(True)
        self.progress.hide(); self.cancel_button.hide(); self.update_models(); self.update_recording()
        self.settings_operation = None; self.settings_progress.hide(); self.settings_cancel.hide()
        if self.close_pending:
            self.close()

    def cancel_current(self):
        self.cancel.set()
        if self.settings_operation:
            self.settings_feedback_text.setText("Cancelling download… Unfinished downloads will need to start again.")
            self.settings_cancel.setEnabled(False)

    def switch_page(self, index):
        try:
            self.flush()
        except Exception as error:
            self.show_error(str(error)); return
        self.pages.setCurrentIndex(index)
        for i, control in enumerate(self.navigation):
            control.setChecked(i == index)
        if index == 2:
            old = self.addresses.currentText(); self.addresses.clear(); self.addresses.addItems(local_addresses()); self.addresses.setCurrentText(old)

    def reload(self, meeting_id=None):
        self.loading = True
        try:
            meetings = self.store.meetings(self.search.text()); self.meeting_list.clear(); selected = None
            for meeting in meetings:
                date = datetime.fromtimestamp(meeting["createdAt"]).strftime("%d %b · %H:%M")
                seconds = meeting["capturedSampleCount"] // 16000
                item = QListWidgetItem(meeting["title"] + "\n" + date + (f"   {seconds // 60} min" if seconds else "   Notes"))
                item.setData(Qt.UserRole, meeting["id"]); self.meeting_list.addItem(item)
                if meeting["id"] == meeting_id:
                    selected = item
            self.meeting_count.setText(f"{len(meetings)} meeting" + ("s" if len(meetings) != 1 else ""))
            self.meeting_list.setCurrentItem(selected)
        finally:
            self.loading = False
        self.load_meeting(meeting_id if selected else None)

    def meeting_changed(self, current, previous):
        if self.loading:
            return
        try:
            self.flush(); self.load_meeting(current.data(Qt.UserRole) if current else None)
        except Exception as error:
            self.show_error(str(error))

    def load_meeting(self, meeting_id):
        self.loading = True
        try:
            self.playback.stop()
            self.selected = self.store.get("meeting", meeting_id) if meeting_id else None
            self.detail_stack.setCurrentIndex(1 if self.selected else 0)
            if not self.selected:
                return
            self.title.setText(self.selected["title"])
            self.metadata.setText(datetime.fromtimestamp(self.selected["createdAt"]).strftime("%A, %d %B %Y  ·  %H:%M"))
            note = self.store.get("note", meeting_id) or {}
            self.note_revision = note.get("editRevision", 0); self.saved_note = note.get("text", ""); self.notes.setPlainText(self.saved_note)
            self.summary = self.store.summary(meeting_id); self.saved_summary = (self.summary or {}).get("editedText", "")
            self.summary_text.setPlainText(self.saved_summary); self.summary_text.setReadOnly(self.summary is None)
            self.transcript_search.clear(); self.refresh_transcript(); self.answers.clear()
            for document in self.store.documents(meeting_id):
                if document["kind"] == "question_answer":
                    item = QListWidgetItem((document["question"] or "Answer") + "\n\n" + document["editedText"]); item.setData(Qt.UserRole, document); self.answers.addItem(item)
        finally:
            self.loading = False

    def flush(self):
        if self.loading or not self.selected:
            return
        if hasattr(self, "notes_timer"):
            self.notes_timer.stop()
        text = self.notes.toPlainText()
        if text != self.saved_note:
            note = self.store.save_note(self.selected["id"], text, self.note_revision)
            self.note_revision, self.saved_note = note["editRevision"], text
            self.show_status("Notes saved on this device")
        text = self.summary_text.toPlainText()
        if self.summary and text != self.saved_summary:
            self.summary = self.store.edit_document(self.summary, text); self.saved_summary = text

    def notes_changed(self):
        if not self.loading and self.selected:
            self.notes_timer.start()

    def new_meeting(self):
        if self.busy or self.recorder.active:
            self.show_status("Finish the active operation first."); return
        title, accepted = QInputDialog.getText(self, "New meeting", "Meeting title", text="New meeting")
        if accepted and title.strip():
            self.invoke(lambda: (self.flush(), self.reload(self.store.create(title)["id"]), self.switch_page(0), self.tabs.setCurrentIndex(2)))

    def refresh_transcript(self):
        self.transcript_list.clear()
        if not self.selected:
            return
        query = self.transcript_search.text().casefold()
        for segment in self.store.transcript(self.selected["id"]):
            if query not in segment["text"].casefold():
                continue
            seconds = segment["startSample"] // 16000
            item = QListWidgetItem(f"{seconds // 60:02}:{seconds % 60:02}\n{segment['text']}"); item.setData(Qt.UserRole, segment); self.transcript_list.addItem(item)

    def seek_transcript(self, item):
        self.play_audio(item.data(Qt.UserRole)["startSample"])

    def play_audio(self, position):
        if self.selected:
            if self.recorder.active:
                self.show_status("Stop recording before playback."); return
            self.invoke(lambda: self.playback.play(self.profile.meeting_dir(self.selected["id"]), position, self.bridge.message.emit))

    def generate(self, question):
        if not self.selected or self.recorder.active:
            self.show_status("Choose a finished meeting first."); return
        meeting = dict(self.selected)
        self.run_work(lambda progress, cancel: self.intelligence.generate(meeting, question, progress, cancel), lambda result: (self.load_meeting(meeting["id"]), self.show_status("Generated content saved with source references")))

    def ask(self):
        if self.question.text().strip():
            self.generate(self.question.text().strip())

    def show_sources(self, document):
        if not self.selected:
            return
        sources = library.document_evidence(document, self.store.transcript(self.selected["id"]))
        dialog = QDialog(self); dialog.setWindowTitle("Sources"); dialog.resize(620, 480)
        layout = QVBoxLayout(dialog); layout.setContentsMargins(24, 24, 24, 24)
        layout.addWidget(label("From the original conversation", "section"))
        listing = QListWidget(); listing.setWordWrap(True)
        for source in sources:
            seconds = source["startSample"] // 16000
            item = QListWidgetItem(f"{seconds // 60:02}:{seconds % 60:02}\n{source['text']}"); item.setData(Qt.UserRole, source); listing.addItem(item)
        listing.itemDoubleClicked.connect(lambda item: self.play_audio(item.data(Qt.UserRole)["startSample"]))
        layout.addWidget(listing); layout.addWidget(label("Double-click a source to play its original audio.", "muted")); dialog.exec()

    def show_summary_sources(self):
        if self.summary:
            self.invoke(lambda: self.show_sources(self.summary))

    def open_answer(self, item):
        document = item.data(Qt.UserRole)
        dialog = QDialog(self); dialog.setWindowTitle("Saved answer"); dialog.resize(650, 500)
        layout = QVBoxLayout(dialog); layout.setContentsMargins(24, 24, 24, 24); layout.addWidget(label(document["question"] or "Answer", "section", True))
        editor = QPlainTextEdit(document["editedText"]); layout.addWidget(editor)
        def save():
            try:
                self.store.edit_document(document, editor.toPlainText()); dialog.accept(); self.load_meeting(self.selected["id"])
            except Exception as error:
                self.show_error(str(error))
        layout.addWidget(row(button("Sources", lambda: self.invoke(lambda: self.show_sources(document))), None, button("Save", save, "primary"))); dialog.exec()

    def meeting_menu(self):
        if not self.selected:
            return
        menu = QMenu(self)
        for title, action in (("Rename", self.rename_meeting), ("Export meeting text", self.export_text), ("Delete summaries", self.delete_summaries), ("Delete meeting…", self.delete_meeting)):
            menu.addAction(title, lambda checked=False, a=action: self.invoke(a))
        menu.exec(self.cursor().pos())

    def rename_meeting(self):
        title, accepted = QInputDialog.getText(self, "Rename meeting", "Meeting title", text=self.selected["title"])
        if accepted:
            self.flush(); self.store.rename(self.selected["id"], title); self.reload(self.selected["id"])

    def delete_summaries(self):
        if QMessageBox.question(self, "Delete summaries", "Delete the saved summaries for this meeting? Audio, transcript, notes and answers remain.") == QMessageBox.Yes:
            self.store.execute("DELETE FROM generated_documents WHERE meeting_id=? AND kind='summary'", (self.selected["id"],)); self.load_meeting(self.selected["id"])

    def delete_meeting(self):
        if self.busy or self.recorder.active:
            raise ValueError("Finish the current operation first.")
        if QMessageBox.question(self, "Delete meeting", "Delete this meeting and its audio from this PC? A copy on your iPhone can return on the next sync.") == QMessageBox.Yes:
            self.playback.stop(); library.delete_meeting(self.profile, self.store, self.selected["id"]); self.reload()

    def export_text(self):
        self.flush()
        filename, _ = QFileDialog.getSaveFileName(self, "Export meeting", "meeting.md", "Text files (*.md *.txt)")
        if filename:
            text = self.selected["title"] + "\n\nNotes\n" + self.saved_note + "\n\nTranscript\n" + "\n\n".join(segment["text"] for segment in self.store.transcript(self.selected["id"])) + "\n\n" + self.saved_summary
            atomic_write(Path(filename), text.encode("utf-8"))

    def toggle_recording(self):
        if self.recorder.active:
            self.run_work(lambda progress, cancel: self.recorder.stop(), lambda _: self.open_recording())
        elif self.microphones.currentData() is not None:
            device = self.microphones.currentData(); self.live.clear()
            self.run_work(lambda progress, cancel: (progress("Preparing the microphone and speech model…"), self.playback.stop(), self.recorder.start(device, cancel)))
        else:
            self.show_status("Connect a microphone, then reopen LocalMinutes.")

    def update_recording(self):
        seconds = int(time.monotonic() - self.recorder.started) if self.recorder.active else 0
        self.timer.setText(f"{seconds // 3600:02}:{seconds // 60 % 60:02}:{seconds % 60:02}")
        self.record_button.setText("Stop recording" if self.recorder.active else "Start recording")
        self.record_button.setEnabled(not self.busy)
        self.record_state.setText("Recording · Original audio is saved locally" if self.recorder.active and not self.recorder.error else "Recording interrupted — stop to finish saving" if self.recorder.active else "Ready when you are")
        self.update_settings_controls()

    def open_recording(self):
        if self.recorder.meeting_id:
            self.reload(self.recorder.meeting_id); self.switch_page(0); self.tabs.setCurrentIndex(1)

    def update_models(self):
        selected = self.models.selected
        if selected and self.models.present(selected):
            self.model_status.setText("In use: " + self.models.name(selected))
        elif selected:
            self.model_status.setText("Selected model needs downloading: " + self.models.name(selected))
        else:
            self.model_status.setText("No model in use. Download a model below, then choose Use model.")
        self.speech_available = self.models.speech_present
        self.speech_removable = any((self.models.speech_directory / filename).exists()
                                    for name, _, _ in SPEECH_FILES for filename in (name, name + ".partial"))
        self.speech_status.setText("Parakeet v3 is downloaded and will be used for recording." if self.speech_available
                                   else "Parakeet v3 converts your voice into text. Download it before your first recording.")
        self.speech_download.setText("Download speech model again" if self.speech_available else "Download speech model · 2.55 GB")
        self.speech_download.setObjectName("quiet" if self.speech_available else "primary")
        self.speech_download.style().unpolish(self.speech_download); self.speech_download.style().polish(self.speech_download)
        self.speech_remove.setVisible(self.speech_removable)
        self.update_model_details()

    def populate_model_choices(self):
        self.model_choices.blockSignals(True)
        self.model_choices.clear()
        for model in self.models.summaries:
            if model["group"] == self.model_groups.currentData():
                self.model_choices.addItem(self.models.name(model), model)
        for index in range(self.model_choices.count()):
            if self.model_choices.itemData(index)["id"] == self.models.selected_id:
                self.model_choices.setCurrentIndex(index)
                break
        self.model_choices.blockSignals(False)
        self.update_model_details()

    def update_model_details(self):
        model = self.model_choices.currentData()
        if not model:
            return
        lines = [model["detail"]]
        if preset := model.get("inferencePreset"):
            lines.append(f"{model['parameterCountBillions']:g}B stored parameters · {model['quantization']} · native context up to {model['contextWindow']['maximumTokens']:,} tokens")
            lines.append("CUDA + CPU/system RAM · offloading allowed" if model["allowCpuOffload"] else "GPU only · all model tensors and KV cache · CPU fallback disabled")
            lines.append("Thinking on · automatic context allocation · no fixed generation budget · Flash Attention · Q8 KV cache")
            lines.append(f"Temperature {preset['temperature']:g} · top-p {preset['topP']:g} · top-k {preset['topK']} · min-p {preset['minP']:g}")
            lines.append(f"Batch {preset['batchSize']} / microbatch {preset['microBatchSize']} · {preset['threads']} host threads for coordination")
        else:
            lines.append(f"GGUF · compatible with the bundled NVIDIA CUDA engine · model context up to {model['contextWindow']['maximumTokens']:,} tokens")
        self.model_details.setText("\n".join(lines))
        guidance = {
            "hybrid": "Highest weight precision. These large downloads also use system memory and may run more slowly.",
            "gpuLarge": "Larger models with compressed weights to fit on the graphics card. Less room for long meetings than the smaller choices.",
            "medium": "Smaller downloads than Large, with more room for long meetings on the graphics card.",
            "small": "The smallest downloads and lowest graphics-memory needs in this catalog.",
        }
        self.model_guidance.setText(guidance.get(model["group"], model["detail"]))
        self.model_available = self.models.present(model)
        self.model_in_use = self.model_available and model["id"] == self.models.selected_id
        path = self.models.path(model)
        self.model_removable = path.exists() or path.with_name(path.name + ".partial").exists()
        state = "In use" if self.model_in_use else "Downloaded · ready to use" if self.model_available else "Not downloaded"
        recommendation = " · Recommended" if model["id"] == self.models.recommended_id else ""
        self.model_candidate_status.setText(f"{state} · {model['byteCount'] / 1000000000:.2f} GB{recommendation}")
        self.model_action.setText("In use" if self.model_in_use else "Use model" if self.model_available else f"Download model · {model['byteCount'] / 1000000000:.2f} GB")
        self.model_remove.setVisible(self.model_removable)
        self.model_repair.setVisible(self.model_available)
        # Keep downloaded/active alternatives discoverable without changing selection.
        for index in range(self.model_choices.count()):
            candidate = self.model_choices.itemData(index)
            present = self.models.present(candidate)
            suffix = " — In use" if present and candidate["id"] == self.models.selected_id else " — Downloaded" if present else ""
            self.model_choices.setItemText(index, self.models.name(candidate) + suffix)
        self.model_choices.setToolTip(self.model_choices.currentText())
        self.update_settings_controls()

    def update_settings_controls(self):
        available = not self.busy and not self.recorder.active
        self.model_action.setEnabled(available and not getattr(self, "model_in_use", False))
        self.model_remove.setEnabled(available)
        self.model_repair.setEnabled(available)
        self.speech_download.setEnabled(available)
        self.speech_remove.setEnabled(available)
        self.library_import.setEnabled(available); self.library_export.setEnabled(available)
        reason = "Stop recording before changing models or transferring your library." if self.recorder.active else "Model and library changes are paused until the current operation finishes."
        self.settings_availability.setText(reason)
        self.settings_availability.setVisible(not available)

    def settings_ready(self):
        if self.busy or self.recorder.active:
            self.show_status("Finish the current operation or stop recording before changing models.")
            return False
        return True

    def activate_model(self):
        if self.models.present(self.model_choices.currentData()):
            self.equip_model()
        else:
            self.download_model()

    def download_with_feedback(self, title, action, completion):
        if not self.settings_ready():
            return
        if self.run_work(action, lambda _: self.show_work_status(completion)):
            self.settings_operation = title
            self.settings_feedback_title.setText(title)
            self.settings_feedback_text.setText("Preparing download…")
            self.settings_cancel.setEnabled(True); self.settings_cancel.show(); self.settings_progress.show()
            self.settings_feedback.show()

    def download_model(self):
        model = self.model_choices.currentData()
        self.download_with_feedback(self.models.name(model), lambda progress, cancel: self.models.download_summary(model, progress, cancel),
                                    "Download complete. Choose Use model to use it for summaries and answers.")

    def equip_model(self):
        if self.settings_ready():
            model = self.model_choices.currentData()
            self.invoke(lambda: (self.models.equip(model), self.update_models(), self.show_status("Now using " + self.models.name(model))))
            self.settings_feedback.hide()

    def download_speech(self):
        self.download_with_feedback("Parakeet v3 speech model", lambda progress, cancel: self.models.download_speech(progress, cancel),
                                    "Speech model downloaded. You can now start a recording.")

    def remove_model(self):
        if not self.settings_ready():
            return
        model = self.model_choices.currentData()
        text = f"Remove {self.models.name(model)} from this PC?\n\nYour meetings and saved summaries will stay. You will need to download the model again to use it."
        if model["id"] == self.models.selected_id:
            text += "\n\nThis model is in use. Choose another downloaded model to generate new summaries and answers."
        if QMessageBox.question(self, "Remove summary model?", text, QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
            self.run_work(lambda progress, cancel: self.models.remove_summary(model), lambda _: self.show_status("Model removed. Your meetings are unchanged."))

    def remove_speech(self):
        if self.settings_ready() and QMessageBox.question(self, "Remove speech model?", "Remove Parakeet v3 from this PC?\n\nYour recordings and transcripts will stay. Download it again before starting another recording.", QMessageBox.Yes | QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
            self.run_work(lambda progress, cancel: self.models.remove_speech(), lambda _: self.show_status("Speech model removed. Your recordings are unchanged."))

    def save_settings(self):
        if not hasattr(self, "dark"):
            return
        self.settings.pop("useGpu", None)
        self.settings.update(dark=self.dark.isChecked())
        self.update_model_details()
        self.invoke(lambda: atomic_write(self.settings_path, json_bytes(self.settings)))
        apply_theme(QApplication.instance(), self.dark.isChecked())

    def pair(self):
        def show():
            invitation = self.sync.invite(self.addresses.currentText())
            code = "localminutes://pair/" + base64.b64encode(json_bytes(invitation)).decode("ascii")
            dialog = QDialog(self); self.pair_dialog = dialog; dialog.setWindowTitle("Pair your iPhone"); dialog.resize(520, 600)
            layout = QVBoxLayout(dialog); layout.setContentsMargins(28, 28, 28, 28)
            layout.addWidget(label("Bring your devices together.", "section"))
            layout.addWidget(label("Open Sync on iPhone and scan this code.\nThis invitation expires in five minutes.", "muted", True))
            matrix = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=4); matrix.add_data(code); matrix.make(fit=True); values = matrix.get_matrix()
            size = len(values) * 4; image = QImage(size, size, QImage.Format_RGB32); image.fill(Qt.white); painter = QPainter(image)
            for y, line in enumerate(values):
                for x, filled in enumerate(line):
                    if filled:
                        painter.fillRect(x * 4, y * 4, 4, 4, Qt.black)
            painter.end(); qr = QLabel(); qr.setPixmap(QPixmap.fromImage(image)); qr.setAlignment(Qt.AlignCenter); layout.addWidget(qr, 1)
            layout.addWidget(row(button("Copy connection code", lambda: QApplication.clipboard().setText(code)), None, button("Done", dialog.accept)))
            dialog.exec(); self.pair_dialog = None
        self.invoke(show)

    def send(self):
        if self.recorder.active:
            self.show_status("Stop recording before syncing."); return
        self.run_work(lambda progress, cancel: self.sync.queue_send(cancel))

    def forget(self):
        if QMessageBox.question(self, "Forget pairing", "Forget paired devices? They will need to pair again.") == QMessageBox.Yes:
            self.invoke(self.sync.forget)

    def request_import(self):
        request = dict(event=threading.Event(), error=None)
        self.bridge.prepare_import.emit(request)
        deadline = time.monotonic() + 30
        while not request["event"].wait(0.1):
            if self.sync.stopping.is_set():
                raise InterruptedError("Sync is closing.")
            if time.monotonic() > deadline:
                raise ValueError("Library preparation timed out.")
        if request["error"]:
            raise ValueError(request["error"])

    def begin_import(self, request):
        try:
            if self.busy or self.recorder.active or self.close_pending or self.sync.stopping.is_set():
                raise ValueError("Finish the active operation before syncing.")
            self.flush(); self.playback.stop(); self.busy = True; self.detail.setEnabled(False); self.meeting_list.setEnabled(False); self.search.setEnabled(False)
            self.update_settings_controls()
        except Exception as error:
            request["error"] = str(error)
        finally:
            request["event"].set()

    def end_import(self):
        self.busy = False; self.detail.setEnabled(True); self.meeting_list.setEnabled(True); self.search.setEnabled(True)
        self.update_settings_controls()
        if self.close_pending:
            self.close()

    def import_library(self):
        if self.recorder.active:
            self.show_status("Stop recording before importing."); return
        directory = QFileDialog.getExistingDirectory(self, "Choose an iPhone backup or LocalMinutes exchange folder")
        if not directory:
            return
        if QMessageBox.question(self, "Import library", "Incoming edits replace matching local edits. Receiver-only meetings remain. Continue?") != QMessageBox.Yes:
            return
        def run(progress, cancel):
            source = Path(directory)
            if not (source / "records.jsonl").is_file():
                progress("Verifying the iPhone backup…")
                source = library.convert_ios_backup(source, self.profile.root / "imports" / identifier(), identifier(), cancel)
            progress("Verifying and saving the library…")
            return exchange.apply(self.profile, self.store, source, cancel)
        self.run_work(run, lambda result: (self.reload(), self.show_status(f"Imported {result['meetings']} meeting records")))

    def export_library(self):
        if self.recorder.active:
            self.show_status("Stop recording before exporting."); return
        parent = QFileDialog.getExistingDirectory(self, "Choose a destination for the exported library")
        if parent:
            destination = Path(parent) / ("LocalMinutes-" + time.strftime("%Y%m%d-%H%M%S") + ".lmtransfer")
            self.run_work(lambda progress, cancel: exchange.create(self.profile, self.store, destination, cancel), lambda _: self.show_status("Library exported to " + str(destination)))

    def show_licenses(self):
        directory = assets() / "licenses"
        if not directory.exists():
            directory = Path(__file__).resolve().parent.parent / "licenses"
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(directory)))

    def closeEvent(self, event):
        if self.preview:
            self.clock.stop(); self.playback.stop(); self.sync.close(); event.accept(); return
        if self.busy:
            self.close_pending = True; self.cancel.set(); self.sync.stopping.set()
            self.show_status("Finishing saved work before closing…"); event.ignore(); return
        if self.recorder.active:
            if QMessageBox.question(self, "Close LocalMinutes", "Stop and save the recording before closing?") != QMessageBox.Yes:
                event.ignore(); return
            self.close_pending = True; self.run_work(lambda progress, cancel: self.recorder.stop()); event.ignore(); return
        try:
            self.flush(); self.sync.close(); self.playback.stop(); self.clock.stop(); event.accept()
        except Exception as error:
            self.close_pending = False; event.ignore(); self.show_error(str(error))
