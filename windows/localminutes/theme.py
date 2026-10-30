"""Quiet desktop surfaces, system typography, and immediate input feedback."""

from PySide6.QtGui import QFont, QPalette, QColor


def apply_theme(app, dark=False):
    colors = dict(canvas="#f5f5f7", sidebar="#edeef2", surface="#ffffff", ink="#1d1d1f", muted="#63636b", line="#dedee4", accent="#007aff", selected="#e1edff", hover="#e9e9ef")
    if dark:
        colors.update(canvas="#202124", sidebar="#25262a", surface="#2d2e33", ink="#f5f5f7", muted="#b2b2bb", line="#42434a", accent="#4b9bff", selected="#28446a", hover="#37383f")
    palette = QPalette()
    for role, key in ((QPalette.Window, "canvas"), (QPalette.WindowText, "ink"), (QPalette.Base, "surface"),
                      (QPalette.Text, "ink"), (QPalette.Button, "surface"), (QPalette.ButtonText, "ink"),
                      (QPalette.Highlight, "selected"), (QPalette.HighlightedText, "ink"), (QPalette.PlaceholderText, "muted")):
        palette.setColor(role, QColor(colors[key]))
    app.setPalette(palette)
    font = QFont("Segoe UI Variable Text", 10)
    app.setFont(font)
    app.setStyleSheet("""
        QWidget { color: %(ink)s; font-family: 'Segoe UI Variable Text', 'Segoe UI'; font-size: 14px; }
        QMainWindow, QDialog { background: %(canvas)s; }
        QWidget#sidebar { background: %(sidebar)s; border-right: 1px solid %(line)s; }
        QWidget#meetingColumn { background: %(surface)s; border-right: 1px solid %(line)s; }
        QWidget#readingSurface, QFrame#group { background: %(surface)s; border-radius: 14px; }
        QLabel { background: transparent; }
        QLabel#title { font-size: 27px; font-weight: 600; letter-spacing: -0.5px; }
        QLabel#section { font-size: 19px; font-weight: 600; }
        QLabel#brand { font-size: 19px; font-weight: 600; }
        QLabel#muted { color: %(muted)s; font-size: 13px; }
        QLabel#timer { font-size: 54px; font-weight: 300; }
        QPushButton { background: %(surface)s; border: 1px solid %(line)s; border-radius: 9px; padding: 8px 15px; font-weight: 500; }
        QPushButton:hover { background: %(hover)s; }
        QPushButton:pressed { background: %(selected)s; }
        QPushButton:focus { border: 2px solid %(accent)s; padding: 7px 14px; }
        QPushButton:disabled { color: %(muted)s; }
        QPushButton#primary { background: %(accent)s; color: white; border-color: %(accent)s; }
        QPushButton#primary:hover { background: #006be0; }
        QPushButton#record { background: #e84646; color: white; border: none; padding: 13px 22px; border-radius: 24px; }
        QPushButton#record:pressed { background: #ba3030; }
        QPushButton#navigation { text-align: left; border: none; padding: 11px 15px; background: transparent; }
        QPushButton#navigation:hover { background: %(hover)s; }
        QPushButton#navigation:checked { background: %(selected)s; color: %(accent)s; font-weight: 600; }
        QPushButton#quiet { background: transparent; border: none; color: %(accent)s; }
        QLineEdit, QComboBox { background: %(surface)s; border: 1px solid %(line)s; padding: 9px 12px; border-radius: 9px; selection-background-color: %(selected)s; }
        QLineEdit:focus, QComboBox:focus { border: 1px solid %(accent)s; }
        QComboBox QAbstractItemView { background: %(surface)s; border: 1px solid %(line)s; selection-background-color: %(selected)s; padding: 6px; }
        QComboBox::drop-down { border: none; width: 25px; }
        QPlainTextEdit, QTextEdit { background: %(surface)s; border: none; border-radius: 10px; padding: 15px; font-size: 15px; selection-background-color: %(selected)s; }
        QListWidget { background: transparent; border: none; outline: none; }
        QListWidget::item { padding: 12px; border-radius: 10px; margin: 2px 8px; }
        QListWidget::item:selected { background: %(selected)s; }
        QListWidget::item:hover { background: %(hover)s; }
        QTabWidget::pane { border: none; background: %(surface)s; border-radius: 12px; }
        QTabBar::tab { background: transparent; padding: 9px 23px; color: %(muted)s; border-radius: 8px; margin: 5px 2px; }
        QTabBar::tab:selected { background: %(surface)s; color: %(ink)s; font-weight: 600; }
        QTabBar { background: %(sidebar)s; border-radius: 10px; }
        QScrollArea { border: none; background: transparent; }
        QScrollBar:vertical { width: 9px; background: transparent; margin: 2px; }
        QScrollBar::handle:vertical { background: %(line)s; border-radius: 3px; min-height: 30px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        QProgressBar { background: %(line)s; border: none; border-radius: 3px; height: 5px; }
        QProgressBar::chunk { background: %(accent)s; border-radius: 3px; }
        QCheckBox { spacing: 10px; padding: 7px 0; }
        QCheckBox::indicator { width: 17px; height: 17px; }
        QSplitter::handle { background: %(line)s; width: 1px; }
        QMenu { background: %(surface)s; padding: 6px; border: 1px solid %(line)s; border-radius: 9px; }
        QMenu::item { padding: 8px 22px; border-radius: 6px; }
        QMenu::item:selected { background: %(selected)s; }
        QToolTip { background: %(surface)s; color: %(ink)s; border: 1px solid %(line)s; padding: 6px; }
    """ % colors)
    return colors
