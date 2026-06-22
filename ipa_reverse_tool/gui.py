from __future__ import annotations

import platform
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QEvent, QObject, QStandardPaths, QThread, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices, QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from .core.ipa_analyzer import IpaAnalysisResult, analyze_ipa
from .core.tool_locator import app_base_dir


class IpaApplication(QApplication):
    file_opened = Signal(str)

    def event(self, event: QEvent) -> bool:
        if event.type() == QEvent.Type.FileOpen:
            path = event.file()
            if path:
                self.file_opened.emit(path)
                return True
        return super().event(event)


class AnalysisWorker(QObject):
    finished = Signal(object)
    failed = Signal(str)
    log = Signal(str)

    def __init__(self, ipa_path: Path, output_dir: Path) -> None:
        super().__init__()
        self.ipa_path = ipa_path
        self.output_dir = output_dir

    @Slot()
    def run(self) -> None:
        try:
            self.log.emit(f"校验 IPA：{self.ipa_path}")
            self.log.emit(f"输出目录：{self.output_dir}")
            self.log.emit("正在解包并分析 Info.plist、资源和敏感字符串...")
            result = analyze_ipa(self.ipa_path, self.output_dir)
            self.finished.emit(result)
        except Exception as exc:
            self.failed.emit(str(exc))


class DropArea(QFrame):
    ipa_dropped = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.setAcceptDrops(True)
        self.setObjectName("dropArea")
        self.setMinimumHeight(180)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 28, 28, 28)
        layout.setSpacing(8)
        title = QLabel("拖入 IPA")
        title.setObjectName("dropTitle")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle = QLabel("将一个 .ipa 文件拖到这里，或点击下方选择文件")
        subtitle.setObjectName("dropSubtitle")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addStretch()
        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addStretch()

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if self._first_ipa(event.mimeData().urls()):
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent) -> None:
        ipa_path = self._first_ipa(event.mimeData().urls())
        if ipa_path:
            self.ipa_dropped.emit(ipa_path)
            event.acceptProposedAction()

    @staticmethod
    def _first_ipa(urls: list[QUrl]) -> str:
        for url in urls:
            path = url.toLocalFile()
            if path.lower().endswith(".ipa"):
                return path
        return ""


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.worker_thread: QThread | None = None
        self.worker: AnalysisWorker | None = None
        self.last_report: Path | None = None
        self.setWindowTitle("IPA Reverse Analysis Tool")
        self.resize(860, 690)
        self.setMinimumSize(720, 580)
        self.setAcceptDrops(True)
        self._build_ui()
        self._apply_style()

    def _build_ui(self) -> None:
        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(26, 24, 26, 24)
        layout.setSpacing(14)

        heading = QLabel("IPA Reverse Analysis Tool")
        heading.setObjectName("heading")
        summary = QLabel("iOS IPA 静态分析、资源扫描与结构化报告")
        summary.setObjectName("summary")
        layout.addWidget(heading)
        layout.addWidget(summary)

        self.drop_area = DropArea()
        self.drop_area.ipa_dropped.connect(self.set_ipa_path)
        layout.addWidget(self.drop_area)

        ipa_row = QHBoxLayout()
        self.ipa_input = QLineEdit()
        self.ipa_input.setPlaceholderText("选择或拖入 .ipa 文件")
        choose_ipa = QPushButton("选择 IPA")
        choose_ipa.clicked.connect(self.choose_ipa)
        ipa_row.addWidget(self.ipa_input, 1)
        ipa_row.addWidget(choose_ipa)
        layout.addLayout(ipa_row)

        output_row = QHBoxLayout()
        self.output_input = QLineEdit(str(self.default_output_root()))
        choose_output = QPushButton("输出目录")
        choose_output.clicked.connect(self.choose_output)
        output_row.addWidget(self.output_input, 1)
        output_row.addWidget(choose_output)
        layout.addLayout(output_row)

        command_row = QHBoxLayout()
        self.analyze_button = QPushButton("开始分析")
        self.analyze_button.setObjectName("primaryButton")
        self.analyze_button.clicked.connect(self.start_analysis)
        doctor_button = QPushButton("环境体检")
        doctor_button.clicked.connect(self.open_environment_doctor)
        self.open_report_button = QPushButton("打开报告")
        self.open_report_button.setEnabled(False)
        self.open_report_button.clicked.connect(self.open_report)
        command_row.addWidget(self.analyze_button)
        command_row.addWidget(doctor_button)
        command_row.addStretch()
        command_row.addWidget(self.open_report_button)
        layout.addLayout(command_row)

        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setRange(0, 1)
        self.progress.setValue(0)
        layout.addWidget(self.progress)

        self.status_label = QLabel("等待 IPA")
        self.status_label.setObjectName("status")
        layout.addWidget(self.status_label)

        self.log_output = QPlainTextEdit()
        self.log_output.setReadOnly(True)
        self.log_output.setPlaceholderText("分析日志会显示在这里")
        self.log_output.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        layout.addWidget(self.log_output, 1)
        self.setCentralWidget(root)

    def _apply_style(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget { background: #f4f6f8; color: #18212b; }
            QLabel#heading { font-size: 26px; font-weight: 700; }
            QLabel#summary { color: #5b6875; font-size: 14px; }
            QFrame#dropArea { background: #ffffff; border: 2px dashed #8aa4be; border-radius: 8px; }
            QLabel#dropTitle { font-size: 24px; font-weight: 650; color: #174f7a; }
            QLabel#dropSubtitle { color: #607386; font-size: 14px; }
            QLineEdit, QPlainTextEdit { background: #ffffff; border: 1px solid #c9d2dc; border-radius: 6px; padding: 9px; }
            QPushButton { background: #ffffff; border: 1px solid #b8c4cf; border-radius: 6px; padding: 9px 16px; }
            QPushButton:hover { background: #edf3f8; }
            QPushButton:disabled { color: #9aa5af; background: #eef1f4; }
            QPushButton#primaryButton { background: #1769aa; color: #ffffff; border-color: #1769aa; font-weight: 650; }
            QPushButton#primaryButton:hover { background: #12598f; }
            QProgressBar { background: #e0e6eb; border: 0; border-radius: 3px; min-height: 6px; max-height: 6px; }
            QProgressBar::chunk { background: #1769aa; border-radius: 3px; }
            QLabel#status { color: #405364; font-weight: 600; }
            """
        )

    @staticmethod
    def default_output_root() -> Path:
        documents = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DocumentsLocation)
        return Path(documents) / "IPAReverseReports"

    @Slot(str)
    def set_ipa_path(self, path: str) -> None:
        ipa = Path(path).expanduser()
        if ipa.suffix.lower() != ".ipa":
            QMessageBox.warning(self, "文件格式不支持", "请选择 .ipa 文件。")
            return
        self.ipa_input.setText(str(ipa))
        self.status_label.setText(f"已选择：{ipa.name}")

    @Slot()
    def choose_ipa(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "选择 IPA", str(Path.home()), "IPA 文件 (*.ipa)")
        if path:
            self.set_ipa_path(path)

    @Slot()
    def choose_output(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择报告输出目录", self.output_input.text())
        if path:
            self.output_input.setText(path)

    @Slot()
    def start_analysis(self) -> None:
        ipa_path = Path(self.ipa_input.text().strip()).expanduser()
        if not ipa_path.is_file() or ipa_path.suffix.lower() != ".ipa":
            QMessageBox.warning(self, "缺少 IPA", "请先拖入或选择一个有效的 .ipa 文件。")
            return
        output_root = Path(self.output_input.text().strip()).expanduser()
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = output_root / f"{ipa_path.stem}_{timestamp}"
        self._set_busy(True)
        self.log_output.clear()
        self._append_log("开始分析")
        self.worker_thread = QThread(self)
        self.worker = AnalysisWorker(ipa_path, output_dir)
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.log.connect(self._append_log)
        self.worker.finished.connect(self._analysis_finished)
        self.worker.failed.connect(self._analysis_failed)
        self.worker.finished.connect(self.worker_thread.quit)
        self.worker.failed.connect(self.worker_thread.quit)
        self.worker.finished.connect(self.worker.deleteLater)
        self.worker.failed.connect(self.worker.deleteLater)
        self.worker_thread.finished.connect(self.worker_thread.deleteLater)
        self.worker_thread.finished.connect(self._worker_released)
        self.worker_thread.start()

    @Slot()
    def _worker_released(self) -> None:
        self.worker = None
        self.worker_thread = None

    @Slot(object)
    def _analysis_finished(self, result: IpaAnalysisResult) -> None:
        self.last_report = Path(result.output_dir) / "reports" / "reverse_report.html"
        if not self.last_report.exists():
            self.last_report = Path(result.output_dir) / "reports" / "reverse_report.md"
        app_name = result.app_info.get("CFBundleDisplayName") or result.app_info.get("CFBundleName") or "未知 App"
        self._append_log(f"分析完成：{app_name}")
        self._append_log(f"报告：{self.last_report}")
        self.status_label.setText(f"分析完成：{app_name}")
        self.open_report_button.setEnabled(True)
        self._set_busy(False)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.last_report)))

    @Slot(str)
    def _analysis_failed(self, message: str) -> None:
        self._append_log(f"分析失败：{message}")
        self.status_label.setText("分析失败")
        self._set_busy(False)
        QMessageBox.critical(self, "分析失败", message)

    @Slot(str)
    def _append_log(self, message: str) -> None:
        self.log_output.appendPlainText(message)

    def _set_busy(self, busy: bool) -> None:
        self.analyze_button.setEnabled(not busy)
        if busy:
            self.progress.setRange(0, 0)
            self.status_label.setText("正在分析，请稍候...")
        else:
            self.progress.setRange(0, 1)
            self.progress.setValue(1)

    @Slot()
    def open_report(self) -> None:
        if self.last_report and self.last_report.exists():
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.last_report)))

    @Slot()
    def open_environment_doctor(self) -> None:
        base_dir = app_base_dir()
        if platform.system() == "Darwin":
            candidates = [
                base_dir / "doctor" / "macos" / "IPA环境体检.command",
                base_dir.parent / "Resources" / "doctor" / "macos" / "IPA环境体检.command",
            ]
            for candidate in candidates:
                if candidate.exists():
                    subprocess.Popen(["open", str(candidate)])
                    return
        elif platform.system() == "Windows":
            candidate = base_dir / "IPA环境体检.exe"
            if candidate.exists():
                subprocess.Popen([str(candidate)])
                return
        QMessageBox.information(self, "环境体检", "未找到独立环境体检工具，请从安装包根目录运行。")
def run_gui(argv: list[str] | None = None) -> int:
    app = IpaApplication(argv or sys.argv)
    app.setApplicationName("IPA Reverse Analysis Tool")
    window = MainWindow()
    app.file_opened.connect(window.set_ipa_path)
    window.show()
    for argument in (argv or sys.argv)[1:]:
        if argument.lower().endswith(".ipa"):
            window.set_ipa_path(argument)
            break
    return app.exec()
