# -*- coding: utf-8 -*-
import json
import urllib.request
import urllib.error
import subprocess
from pathlib import Path
from datetime import datetime
import sys
import platform

if sys.platform == "win32":
    import winreg

from PySide6.QtCore import *
from PySide6.QtGui import *
from PySide6.QtWidgets import *
from PySide6.QtSvg import QSvgRenderer

# ---------- Cấu hình ----------
APP_TITLE = "LAN Monitor Dashboard"
DEFAULT_PORT = 8765
DEFAULT_TOKEN = "LANMONITOR-CHANGE-ME"
REFRESH_MS = 3000
CONFIG_PATH = None

def get_config_path() -> Path:
    """Tìm file dashboard_config.json một cách thông minh, ưu tiên file có dữ liệu máy tính."""
    candidates = []
    
    # 1. Thư mục chứa file exe (khi chạy bản đóng gói .exe)
    if getattr(sys, 'frozen', False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.append(exe_dir / "dashboard_config.json")
        if exe_dir.name.lower() == "dist":
            candidates.append(exe_dir.parent / "dashboard_config.json")
            
    # 2. Thư mục chứa file mã nguồn
    script_dir = Path(__file__).resolve().parent
    candidates.append(script_dir / "dashboard_config.json")
    
    # 3. Thư mục làm việc hiện tại
    try:
        candidates.append(Path.cwd() / "dashboard_config.json")
    except Exception:
        pass
    candidates.append(Path("dashboard_config.json"))
    
    # Duyệt tìm file tồn tại, ưu tiên file có danh sách hosts
    first_existing = None
    for p in candidates:
        if p.exists() and p.is_file():
            if first_existing is None:
                first_existing = p
            try:
                data = json.loads(p.read_text(encoding="utf-8"))
                if isinstance(data, dict) and data.get("hosts") and len(data["hosts"]) > 0:
                    return p
            except Exception:
                pass
                
    if first_existing:
        return first_existing
        
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent / "dashboard_config.json"
    return script_dir / "dashboard_config.json"
RUN_REG_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
APP_REG_NAME = "LANMonitorDashboard"

def is_autostart_enabled() -> bool:
    if sys.platform != "win32":
        return False
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_REG_KEY, 0, winreg.KEY_READ) as key:
            winreg.QueryValueEx(key, APP_REG_NAME)
            return True
    except Exception:
        return False

def set_autostart(enable: bool) -> tuple[bool, str]:
    if sys.platform != "win32":
        return False, "Tính năng chỉ hỗ trợ trên hệ điều hành Windows"
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_REG_KEY, 0, winreg.KEY_SET_VALUE) as key:
            if enable:
                if getattr(sys, "frozen", False):
                    exe_path = f'"{sys.executable}" --tray'
                else:
                    exe_path = f'"{sys.executable}" "{Path(__file__).resolve()}" --tray'
                winreg.SetValueEx(key, APP_REG_NAME, 0, winreg.REG_SZ, exe_path)
            else:
                try:
                    winreg.DeleteValue(key, APP_REG_NAME)
                except FileNotFoundError:
                    pass
        return True, "Thành công"
    except Exception as e:
        return False, str(e)

# Font chuẩn hệ điều hành Windows (Fluent / Windows 10 & 11)
FONT_FAMILY = "'Segoe UI Variable Text', 'Segoe UI', system-ui, -apple-system, sans-serif"

# ---------- Heroicons (SVG Path Data 24x24) ----------
HEROICONS = {
    "plus": "M12 4.5v15m7.5-7.5h-15",
    "bars_3": "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5",
    "eye": "M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z M15 12a3 3 0 11-6 0 3 3 0 016 0z",
    "eye_slash": "M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88",
    "fit": "M9 9V4.5M9 9H4.5M9 9L3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5l5.25 5.25",
    "sun": "M12 3v2.25m6.364.386l-1.591 1.591M21 12h-2.25m-.386 6.364l-1.591-1.591M12 18.75V21m-4.773-4.227l-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0z",
    "moon": "M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z",
    "pin": "M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21L12 17.25 4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z",
    "globe": "M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418",
    "desktop": "M9 17.25v1.007a3 3 0 01-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0115 18.257V17.25m6-12V15a2.25 2.25 0 01-2.25 2.25H5.25A2.25 2.25 0 013 15V5.25m18 0A2.25 2.25 0 0018.75 3H5.25A2.25 2.25 0 003 5.25m18 0H3",
    "cog": "M10.5 6h9.75M10.5 6a1.5 1.5 0 11-3 0m3 0a1.5 1.5 0 10-3 0M3.75 6H7.5m3 12h9.75m-9.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-3.75 0H7.5m9-6h3.75m-3.75 0a1.5 1.5 0 01-3 0m3 0a1.5 1.5 0 00-3 0m-9.75 0h9.75",
    "power": "M5.636 5.636a9 9 0 1012.728 0M12 3v9",
    "arrow_path": "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99",
    "play": "M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z",
    "trash": "M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0",
    "floating": "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15",
    "close": "M6 18L18 6M6 6l12 12",
    "pencil": "m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10",
    "link": "M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244",
    "swatch": "M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125v4.072M6.75 21a3.75 3.75 0 003.75-3.75V8.197M6.75 21h13.125c.621 0 1.125-.504 1.125-1.125v-5.25c0-.621-.504-1.125-1.125-1.125h-4.072M10.5 8.197l9.75 9.75",
    "squares": "M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z"
}

def heroicon(path_d, color="#94a3b8", size=20, stroke_width="2"):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="{stroke_width}" stroke="{color}"><path stroke-linecap="round" stroke-linejoin="round" d="{path_d}" /></svg>'
    renderer = QSvgRenderer(QByteArray(svg.encode('utf-8')))
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    renderer.render(painter)
    painter.end()
    return QIcon(pixmap)

def get_dashboard_icon() -> QIcon:
    candidates = []
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        candidates.append(Path(sys._MEIPASS) / "app-das.ico")
    base_dir = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent
    candidates.append(base_dir / "app-das.ico")
    candidates.append(Path("app-das.ico"))
    for p in candidates:
        if p.exists():
            return QIcon(str(p))
    return heroicon(HEROICONS["desktop"], "#0284c7", 32)

# ---------- Hệ thống màu giao diện (Themes) ----------
THEMES = {
    "dark": {
        "name": "dark",
        "app_bg": "#0f172a",           # Slate 900
        "card_bg": "#1e293b",          # Slate 800
        "card_border": "#334155",      # Slate 700
        "card_hover": "#475569",
        "card_offline_bg": "#24141a",
        "card_offline_border": "#ef4444",
        "text_primary": "#f8fafc",
        "text_secondary": "#94a3b8",
        "text_muted": "#64748b",
        "badge_ip_bg": "#334155",
        "badge_ip_text": "#cbd5e1",
        "bar_bg": "#334155",
        "bar_normal": "#38bdf8",       # Sky Cyan
        "bar_warn": "#fbbf24",         # Amber
        "bar_danger": "#f87171",       # Rose
        "btn_sec_bg": "#334155",
        "btn_sec_text": "#f1f5f9",
        "btn_sec_hover": "#475569",
        "btn_sec_border": "#475569",
        "btn_pri_bg": "#0284c7",       # Sky 600
        "btn_pri_text": "#ffffff",
        "btn_pri_hover": "#0369a1",
        "toolbar_bg": "#0f172a",
        "toolbar_border": "#1e293b",
        "toolbar_btn_text": "#cbd5e1",
        "toolbar_btn_hover": "#1e293b",
        "status_online": "#10b981",     # Emerald
        "status_offline": "#ef4444",    # Red
        "dialog_bg": "#1e293b",
        "input_bg": "#0f172a",
        "input_border": "#334155",
        "floating_header_bg": "rgba(30, 41, 59, 0.95)",
    },
    "light": {
        "name": "light",
        "app_bg": "#f8fafc",           # Slate 50
        "card_bg": "#ffffff",          # White
        "card_border": "#e2e8f0",      # Slate 200
        "card_hover": "#cbd5e1",
        "card_offline_bg": "#fff1f2",
        "card_offline_border": "#fca5a5",
        "text_primary": "#0f172a",
        "text_secondary": "#64748b",
        "text_muted": "#94a3b8",
        "badge_ip_bg": "#f1f5f9",
        "badge_ip_text": "#475569",
        "bar_bg": "#e2e8f0",
        "bar_normal": "#0284c7",       # Sky Blue
        "bar_warn": "#d97706",         # Amber
        "bar_danger": "#dc2626",       # Red
        "btn_sec_bg": "#f1f5f9",
        "btn_sec_text": "#334155",
        "btn_sec_hover": "#e2e8f0",
        "btn_sec_border": "#cbd5e1",
        "btn_pri_bg": "#0284c7",       # Sky 600
        "btn_pri_text": "#ffffff",
        "btn_pri_hover": "#0369a1",
        "toolbar_bg": "#ffffff",
        "toolbar_border": "#e2e8f0",
        "toolbar_btn_text": "#475569",
        "toolbar_btn_hover": "#f1f5f9",
        "status_online": "#059669",
        "status_offline": "#dc2626",
        "dialog_bg": "#ffffff",
        "input_bg": "#f8fafc",
        "input_border": "#cbd5e1",
        "floating_header_bg": "rgba(255, 255, 255, 0.95)",
    }
}

# ---------- Hàm tiện ích ----------
def load_config():
    default = {
        "token": DEFAULT_TOKEN,
        "theme": "dark",
        "hosts": [],
        "apps": {"Notepad": "notepad.exe", "Chrome": "chrome.exe", "Taskmgr": "taskmgr.exe"},
        "links": {"Google": "https://google.com", "YouTube": "https://youtube.com"},
        "notify_offline": True,
        "hide_offline": False,
        "minimal_style": "twin_rings",
        "minimal_layout": "vertical"
    }
    cfg_path = get_config_path()
    if cfg_path.exists():
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            default.update(data)
            if "links" not in default or not isinstance(default["links"], dict):
                default["links"] = {"Google": "https://google.com", "YouTube": "https://youtube.com"}
            if "apps" not in default or not isinstance(default["apps"], dict):
                default["apps"] = {"Notepad": "notepad.exe", "Chrome": "chrome.exe", "Taskmgr": "taskmgr.exe"}
            if "minimal_style" not in default:
                default["minimal_style"] = "twin_rings"
            if "minimal_layout" not in default:
                default["minimal_layout"] = "vertical"
        except Exception: pass
    return default

def save_config(cfg):
    cfg_path = get_config_path()
    try:
        with open(cfg_path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def fmt_rate(bps):
    units = ["B/s", "KB/s", "MB/s", "GB/s"]
    x = float(bps or 0)
    for u in units:
        if x < 1024 or u == units[-1]: return f"{x:.1f} {u}"
        x /= 1024

def fmt_uptime(sec):
    sec = int(sec or 0)
    if sec <= 0: return ""
    d = sec // 86400
    h = (sec % 86400) // 3600
    m = (sec % 3600) // 60
    if d > 0: return f"{d}d {h}h"
    if h > 0: return f"{h}h {m}m"
    return f"{m}m"

# ---------- Workers ----------
class FetchSignals(QObject):
    finished = Signal(int, object, str)

class FetchWorker(QRunnable):
    def __init__(self, idx, host, token, signals):
        super().__init__()
        self.idx, self.host, self.token = idx, host, token
        self.signals = signals
    @Slot()
    def run(self):
        url = f"http://{self.host['ip']}:{self.host.get('port', DEFAULT_PORT)}/metrics"
        try:
            req = urllib.request.Request(url, headers={"X-LAN-Monitor-Token": self.token})
            with urllib.request.urlopen(req, timeout=2) as r:
                data = json.loads(r.read().decode("utf-8"))
            try:
                self.signals.finished.emit(self.idx, data, "")
            except Exception:
                pass
        except Exception as e:
            try:
                self.signals.finished.emit(self.idx, None, str(e))
            except Exception:
                pass

class ControlWorker(QRunnable):
    class Signals(QObject):
        finished = Signal(str)
    def __init__(self, host, token, action, app_path=None, url=None):
        super().__init__()
        self.host, self.token, self.action, self.app_path, self.url = host, token, action, app_path, url
        self.signals = ControlWorker.Signals()
    @Slot()
    def run(self):
        endpoint = f"http://{self.host['ip']}:{self.host.get('port', DEFAULT_PORT)}/control"
        payload = {"action": self.action}
        if self.app_path: payload["app_path"] = self.app_path
        if self.url: payload["url"] = self.url
        # Fallback compatibility: nếu agent cũ chỉ nhận action run_app cho URL
        if self.action == "open_url" and self.url:
            payload["app_path"] = self.url
        data = json.dumps(payload).encode("utf-8")
        try:
            req = urllib.request.Request(endpoint, data=data, headers={"X-LAN-Monitor-Token": self.token, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=5) as r:
                res = json.loads(r.read().decode("utf-8"))
                self.signals.finished.emit(f"Kết quả [{self.host.get('name')}]: {res.get('message')}")
        except Exception as e: self.signals.finished.emit(f"Lỗi [{self.host.get('name')}]: {str(e)}")

# ---------- UI Components ----------
class HostDialog(QDialog):
    def __init__(self, parent=None, host=None):
        super().__init__(parent)
        self.setWindowTitle("Cấu hình máy")
        self.setFixedWidth(330)
        layout = QFormLayout(self)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(12)
        
        self.name_edit = QLineEdit(host.get("name", "") if host else "")
        self.name_edit.setPlaceholderText("VD: SRO130")
        self.ip_edit = QLineEdit(host.get("ip", "") if host else "")
        self.ip_edit.setPlaceholderText("VD: 192.168.1.4")
        self.port_edit = QLineEdit(str(host.get("port", DEFAULT_PORT)) if host else str(DEFAULT_PORT))
        
        layout.addRow("Tên máy:", self.name_edit)
        layout.addRow("Địa chỉ IP:", self.ip_edit)
        layout.addRow("Cổng (Port):", self.port_edit)
        
        btns = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addRow(btns)

    def get_data(self):
        return {
            "name": self.name_edit.text().strip() or "PC",
            "ip": self.ip_edit.text().strip(),
            "port": int(self.port_edit.text().strip() or DEFAULT_PORT)
        }

class ItemEditDialog(QDialog):
    """Dialog để Thêm hoặc Sửa 1 Ứng dụng hoặc 1 Đường link"""
    def __init__(self, parent=None, mode="app", title="Thêm mới", name="", target="", show_save_checkbox=False):
        super().__init__(parent)
        self.mode = mode  # "app" hoặc "link"
        self.setWindowTitle(title)
        self.setMinimumWidth(380)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 18, 18, 18)
        layout.setSpacing(12)
        
        form = QFormLayout()
        form.setSpacing(10)
        
        self.name_edit = QLineEdit(name)
        if mode == "app":
            self.name_edit.setPlaceholderText("VD: Chrome, UltraViewer, Game...")
        else:
            self.name_edit.setPlaceholderText("VD: Google, YouTube, Web App...")
        form.addRow("Tên hiển thị:", self.name_edit)
        
        target_layout = QHBoxLayout()
        self.target_edit = QLineEdit(target)
        if mode == "app":
            self.target_edit.setPlaceholderText("VD: chrome.exe hoặc C:\\Program Files\\...")
            target_layout.addWidget(self.target_edit)
            self.btn_browse = QPushButton("Chọn file...")
            self.btn_browse.clicked.connect(self._browse_file)
            target_layout.addWidget(self.btn_browse)
            form.addRow("Đường dẫn / Lệnh:", target_layout)
        else:
            self.target_edit.setPlaceholderText("VD: https://google.com")
            target_layout.addWidget(self.target_edit)
            form.addRow("Đường link (URL):", target_layout)
            
        layout.addLayout(form)
        
        self.chk_save = None
        if show_save_checkbox:
            self.chk_save = QCheckBox("Lưu vào danh sách để dùng lại lần sau")
            self.chk_save.setChecked(True)
            layout.addWidget(self.chk_save)
            
        btns = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btns.accepted.connect(self._validate_and_accept)
        btns.rejected.connect(self.reject)
        layout.addWidget(btns)
        
    def _browse_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Chọn file thực thi", "",
            "Tập tin thực thi (*.exe *.bat *.cmd *.lnk);;Tất cả tập tin (*.*)"
        )
        if file_path:
            self.target_edit.setText(file_path)
            if not self.name_edit.text().strip():
                self.name_edit.setText(Path(file_path).stem)

    def _validate_and_accept(self):
        target = self.target_edit.text().strip()
        if not target:
            msg = "Vui lòng nhập đường dẫn ứng dụng!" if self.mode == "app" else "Vui lòng nhập đường link (URL)!"
            QMessageBox.warning(self, "Thiếu thông tin", msg)
            return
        
        name = self.name_edit.text().strip()
        if not name:
            if self.mode == "app":
                name = Path(target).stem or target
            else:
                clean_target = target.replace("https://", "").replace("http://", "").split("/")[0]
                name = clean_target or "Link"
            self.name_edit.setText(name)
            
        if self.mode == "link":
            if not (target.startswith("http://") or target.startswith("https://")):
                target = "https://" + target
                self.target_edit.setText(target)
                
        self.accept()
        
    def get_data(self):
        save_checked = self.chk_save.isChecked() if self.chk_save else False
        return self.name_edit.text().strip(), self.target_edit.text().strip(), save_checked

class AppAndLinkManagerDialog(QDialog):
    """Quản lý danh sách Ứng dụng & Đường link: Thêm, Sửa, Xóa"""
    def __init__(self, main_win, initial_tab=0, parent=None):
        super().__init__(parent or main_win)
        self.main_win = main_win
        self.setWindowTitle("Quản lý Ứng dụng & Đường link từ xa")
        self.setMinimumSize(560, 420)
        self.resize(600, 440)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)
        
        self.tabs = QTabWidget()
        
        # Tab 1: Apps
        tab_apps = QWidget()
        layout_apps = QVBoxLayout(tab_apps)
        layout_apps.setContentsMargins(10, 10, 10, 10)
        layout_apps.setSpacing(8)
        
        lbl_apps_hint = QLabel("Danh sách ứng dụng khởi chạy từ xa trên các máy:")
        lbl_apps_hint.setStyleSheet("color: #94a3b8; font-size: 12px;")
        layout_apps.addWidget(lbl_apps_hint)
        
        self.tbl_apps = QTableWidget()
        self.tbl_apps.setColumnCount(2)
        self.tbl_apps.setHorizontalHeaderLabels(["Tên ứng dụng", "Đường dẫn thực thi / Lệnh"])
        self.tbl_apps.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.tbl_apps.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        self.tbl_apps.setSelectionBehavior(QTableWidget.SelectRows)
        self.tbl_apps.setSelectionMode(QTableWidget.SingleSelection)
        self.tbl_apps.setEditTriggers(QTableWidget.NoEditTriggers)
        layout_apps.addWidget(self.tbl_apps)
        
        bar_apps = QHBoxLayout()
        btn_add_app = QPushButton("Thêm ứng dụng")
        btn_add_app.setIcon(heroicon(HEROICONS["plus"], "#ffffff", 14))
        btn_add_app.clicked.connect(self._add_app)
        
        btn_edit_app = QPushButton("Chỉnh sửa")
        btn_edit_app.setIcon(heroicon(HEROICONS["pencil"], "#ffffff", 14))
        btn_edit_app.clicked.connect(self._edit_app)
        
        btn_del_app = QPushButton("Xóa")
        btn_del_app.setIcon(heroicon(HEROICONS["trash"], "#ef4444", 14))
        btn_del_app.clicked.connect(self._del_app)
        
        bar_apps.addWidget(btn_add_app)
        bar_apps.addWidget(btn_edit_app)
        bar_apps.addWidget(btn_del_app)
        bar_apps.addStretch()
        layout_apps.addLayout(bar_apps)
        
        # Tab 2: Links
        tab_links = QWidget()
        layout_links = QVBoxLayout(tab_links)
        layout_links.setContentsMargins(10, 10, 10, 10)
        layout_links.setSpacing(8)
        
        lbl_links_hint = QLabel("Danh sách đường link mở bằng trình duyệt mặc định trên máy từ xa:")
        lbl_links_hint.setStyleSheet("color: #94a3b8; font-size: 12px;")
        layout_links.addWidget(lbl_links_hint)
        
        self.tbl_links = QTableWidget()
        self.tbl_links.setColumnCount(2)
        self.tbl_links.setHorizontalHeaderLabels(["Tên liên kết", "Đường dẫn URL"])
        self.tbl_links.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.tbl_links.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        self.tbl_links.setSelectionBehavior(QTableWidget.SelectRows)
        self.tbl_links.setSelectionMode(QTableWidget.SingleSelection)
        self.tbl_links.setEditTriggers(QTableWidget.NoEditTriggers)
        layout_links.addWidget(self.tbl_links)
        
        bar_links = QHBoxLayout()
        btn_add_link = QPushButton("Thêm link")
        btn_add_link.setIcon(heroicon(HEROICONS["plus"], "#ffffff", 14))
        btn_add_link.clicked.connect(self._add_link)
        
        btn_edit_link = QPushButton("Chỉnh sửa")
        btn_edit_link.setIcon(heroicon(HEROICONS["pencil"], "#ffffff", 14))
        btn_edit_link.clicked.connect(self._edit_link)
        
        btn_del_link = QPushButton("Xóa")
        btn_del_link.setIcon(heroicon(HEROICONS["trash"], "#ef4444", 14))
        btn_del_link.clicked.connect(self._del_link)
        
        bar_links.addWidget(btn_add_link)
        bar_links.addWidget(btn_edit_link)
        bar_links.addWidget(btn_del_link)
        bar_links.addStretch()
        layout_links.addLayout(bar_links)
        
        self.tabs.addTab(tab_apps, "🚀 Ứng dụng")
        self.tabs.addTab(tab_links, "🌐 Đường link (URL)")
        self.tabs.setCurrentIndex(initial_tab)
        
        layout.addWidget(self.tabs)
        
        # Bottom Close button
        bottom_box = QHBoxLayout()
        bottom_box.addStretch()
        btn_close = QPushButton("Đóng")
        btn_close.clicked.connect(self.accept)
        bottom_box.addWidget(btn_close)
        layout.addLayout(bottom_box)
        
        self._load_apps()
        self._load_links()

    def _load_apps(self):
        apps = self.main_win.cfg.get("apps", {})
        self.tbl_apps.setRowCount(0)
        for row, (name, path) in enumerate(apps.items()):
            self.tbl_apps.insertRow(row)
            self.tbl_apps.setItem(row, 0, QTableWidgetItem(str(name)))
            self.tbl_apps.setItem(row, 1, QTableWidgetItem(str(path)))

    def _load_links(self):
        links = self.main_win.cfg.get("links", {})
        self.tbl_links.setRowCount(0)
        for row, (name, url) in enumerate(links.items()):
            self.tbl_links.insertRow(row)
            self.tbl_links.setItem(row, 0, QTableWidgetItem(str(name)))
            self.tbl_links.setItem(row, 1, QTableWidgetItem(str(url)))

    def _add_app(self):
        dlg = ItemEditDialog(self, mode="app", title="Thêm ứng dụng mới")
        if dlg.exec():
            name, path, _ = dlg.get_data()
            self.main_win.cfg.setdefault("apps", {})[name] = path
            save_config(self.main_win.cfg)
            self._load_apps()

    def _edit_app(self):
        row = self.tbl_apps.currentRow()
        if row < 0:
            QMessageBox.information(self, "Thông báo", "Vui lòng chọn một ứng dụng để chỉnh sửa!")
            return
        old_name = self.tbl_apps.item(row, 0).text()
        old_path = self.tbl_apps.item(row, 1).text()
        
        dlg = ItemEditDialog(self, mode="app", title="Chỉnh sửa ứng dụng", name=old_name, target=old_path)
        if dlg.exec():
            new_name, new_path, _ = dlg.get_data()
            apps = self.main_win.cfg.get("apps", {})
            if old_name != new_name and old_name in apps:
                del apps[old_name]
            apps[new_name] = new_path
            self.main_win.cfg["apps"] = apps
            save_config(self.main_win.cfg)
            self._load_apps()

    def _del_app(self):
        row = self.tbl_apps.currentRow()
        if row < 0:
            QMessageBox.information(self, "Thông báo", "Vui lòng chọn một ứng dụng để xóa!")
            return
        name = self.tbl_apps.item(row, 0).text()
        if QMessageBox.question(self, "Xác nhận xóa", f"Bạn có chắc muốn xóa ứng dụng '{name}' khỏi danh sách?") == QMessageBox.Yes:
            apps = self.main_win.cfg.get("apps", {})
            if name in apps:
                del apps[name]
                save_config(self.main_win.cfg)
                self._load_apps()

    def _add_link(self):
        dlg = ItemEditDialog(self, mode="link", title="Thêm đường link mới")
        if dlg.exec():
            name, url, _ = dlg.get_data()
            self.main_win.cfg.setdefault("links", {})[name] = url
            save_config(self.main_win.cfg)
            self._load_links()

    def _edit_link(self):
        row = self.tbl_links.currentRow()
        if row < 0:
            QMessageBox.information(self, "Thông báo", "Vui lòng chọn một đường link để chỉnh sửa!")
            return
        old_name = self.tbl_links.item(row, 0).text()
        old_url = self.tbl_links.item(row, 1).text()
        
        dlg = ItemEditDialog(self, mode="link", title="Chỉnh sửa đường link", name=old_name, target=old_url)
        if dlg.exec():
            new_name, new_url, _ = dlg.get_data()
            links = self.main_win.cfg.get("links", {})
            if old_name != new_name and old_name in links:
                del links[old_name]
            links[new_name] = new_url
            self.main_win.cfg["links"] = links
            save_config(self.main_win.cfg)
            self._load_links()

    def _del_link(self):
        row = self.tbl_links.currentRow()
        if row < 0:
            QMessageBox.information(self, "Thông báo", "Vui lòng chọn một đường link để xóa!")
            return
        name = self.tbl_links.item(row, 0).text()
        if QMessageBox.question(self, "Xác nhận xóa", f"Bạn có chắc muốn xóa đường link '{name}' khỏi danh sách?") == QMessageBox.Yes:
            links = self.main_win.cfg.get("links", {})
            if name in links:
                del links[name]
                save_config(self.main_win.cfg)
                self._load_links()

class HostCard(QFrame):
    def __init__(self, idx, host, main_win):
        super().__init__()
        self.idx, self.host, self.main_win = idx, host, main_win
        self.is_online = None  # None: Đang kết nối, True: Online, False: Offline
        self.is_floating_card = False
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        
        self.card_layout = QVBoxLayout(self)
        self.card_layout.setContentsMargins(14, 12, 14, 12)
        self.card_layout.setSpacing(7)
        
        # Header: Tên máy + Badge IP + Đèn LED trạng thái
        header = QHBoxLayout()
        header.setSpacing(8)
        
        self.name_lbl = QLabel(host.get("name", "PC"))
        self.name_lbl.setStyleSheet("font-weight: 600; font-size: 15px;")
        
        self.ip_badge = QLabel(f"{host['ip']}:{host.get('port', DEFAULT_PORT)}")
        self.ip_badge.setStyleSheet("border-radius: 4px; padding: 2px 7px; font-size: 12px; font-weight: 500;")
        
        header.addWidget(self.name_lbl)
        header.addWidget(self.ip_badge)
        header.addStretch()
        
        # Đèn LED trạng thái
        status_box = QHBoxLayout()
        status_box.setSpacing(6)
        self.status_dot = QWidget()
        self.status_dot.setFixedSize(8, 8)
        self.status_text = QLabel("Đang kết nối")
        self.status_text.setStyleSheet("font-size: 11px; font-weight: 600;")
        status_box.addWidget(self.status_dot)
        status_box.addWidget(self.status_text)
        
        header.addLayout(status_box)
        self.card_layout.addLayout(header)
        
        # Resource Rows (CPU, RAM, DISK, GPU)
        self.cpu_row, self.cpu_lbl, self.cpu_bar = self._create_metric_row("CPU")
        self.ram_row, self.ram_lbl, self.ram_bar = self._create_metric_row("RAM")
        self.disk_row, self.disk_lbl, self.disk_bar = self._create_metric_row("DISK")
        self.gpu_row, self.gpu_lbl, self.gpu_bar = self._create_metric_row("GPU")
        self.gpu_row.hide()
        
        self.card_layout.addWidget(self.cpu_row)
        self.card_layout.addWidget(self.ram_row)
        self.card_layout.addWidget(self.disk_row)
        self.card_layout.addWidget(self.gpu_row)
        
        # Network & Uptime row
        info_layout = QHBoxLayout()
        self.net_lbl = QLabel("Mạng: Đang kết nối...")
        self.net_lbl.setStyleSheet("font-size: 12px;")
        self.uptime_lbl = QLabel("")
        self.uptime_lbl.setStyleSheet("font-size: 12px;")
        info_layout.addWidget(self.net_lbl)
        info_layout.addStretch()
        info_layout.addWidget(self.uptime_lbl)
        self.card_layout.addLayout(info_layout)
        
        # Action Buttons container (ẩn khi ở chế độ nổi, hiện khi hover chuột)
        self.btn_widget = QWidget()
        btn_layout = QHBoxLayout(self.btn_widget)
        btn_layout.setContentsMargins(0, 4, 0, 0)
        btn_layout.setSpacing(8)
        
        self.btn_ctrl = QPushButton("Điều khiển")
        self.btn_ctrl.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.btn_ctrl.clicked.connect(self.show_menu)
        
        self.btn_rdp = QPushButton("RDP")
        self.btn_rdp.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.btn_rdp.clicked.connect(self.open_rdp)
        
        btn_layout.addWidget(self.btn_ctrl)
        btn_layout.addWidget(self.btn_rdp)
        self.card_layout.addWidget(self.btn_widget)

        self.apply_theme(self.main_win.current_theme)

    def set_floating_mode(self, enabled):
        self.is_floating_card = enabled
        if enabled:
            self.btn_widget.hide()
            self.card_layout.setContentsMargins(10, 8, 10, 8)
            self.card_layout.setSpacing(5)
        else:
            self.btn_widget.show()
            self.card_layout.setContentsMargins(14, 12, 14, 12)
            self.card_layout.setSpacing(7)

    def enterEvent(self, event):
        super().enterEvent(event)
        if self.is_floating_card:
            self.btn_widget.show()

    def leaveEvent(self, event):
        super().leaveEvent(event)
        if self.is_floating_card:
            self.btn_widget.hide()

    def _create_metric_row(self, title):
        container = QWidget()
        vbox = QVBoxLayout(container)
        vbox.setContentsMargins(0, 0, 0, 0)
        vbox.setSpacing(2)
        
        hbox = QHBoxLayout()
        lbl_title = QLabel(title)
        lbl_title.setStyleSheet("font-size: 12px; font-weight: 500;")
        lbl_val = QLabel("0%")
        lbl_val.setStyleSheet("font-size: 12px; font-weight: 600;")
        
        hbox.addWidget(lbl_title)
        hbox.addStretch()
        hbox.addWidget(lbl_val)
        
        bar = QProgressBar()
        bar.setFixedHeight(7)
        bar.setTextVisible(False)
        bar.setRange(0, 100)
        bar.setValue(0)
        
        vbox.addLayout(hbox)
        vbox.addWidget(bar)
        return container, lbl_val, bar

    def _update_bar_style(self, bar, val, t):
        if val >= 85:
            chunk = t["bar_danger"]
        elif val >= 70:
            chunk = t["bar_warn"]
        else:
            chunk = t["bar_normal"]
        bar.setStyleSheet(f"""
            QProgressBar {{
                background-color: {t['bar_bg']};
                border-radius: 3px;
                border: none;
            }}
            QProgressBar::chunk {{
                background-color: {chunk};
                border-radius: 3px;
            }}
        """)

    def apply_theme(self, t):
        if self.is_online is False:
            bg = t["card_offline_bg"]
            border = t["card_offline_border"]
            status_color = t["status_offline"]
            status_txt = "OFFLINE"
        elif self.is_online is True:
            bg = t["card_bg"]
            border = t["card_border"]
            status_color = t["status_online"]
            status_txt = "ONLINE"
        else:
            bg = t["card_bg"]
            border = t["card_border"]
            status_color = t["text_muted"]
            status_txt = "KẾT NỐI"

        self.setStyleSheet(f"""
            HostCard {{
                background-color: {bg};
                border: 1px solid {border};
                border-radius: 10px;
            }}
        """)

        self.name_lbl.setStyleSheet(f"color: {t['text_primary']}; font-weight: 600; font-size: 15px; font-family: {FONT_FAMILY};")
        self.ip_badge.setStyleSheet(f"background-color: {t['badge_ip_bg']}; color: {t['badge_ip_text']}; border-radius: 4px; padding: 2px 7px; font-size: 12px; font-weight: 500; font-family: {FONT_FAMILY};")
        
        self.status_dot.setStyleSheet(f"background-color: {status_color}; border-radius: 4px;")
        self.status_text.setStyleSheet(f"color: {status_color}; font-size: 11px; font-weight: 600; font-family: {FONT_FAMILY};")
        self.status_text.setText(status_txt)

        self.net_lbl.setStyleSheet(f"color: {t['text_secondary']}; font-size: 12px; font-family: {FONT_FAMILY};")
        self.uptime_lbl.setStyleSheet(f"color: {t['text_muted']}; font-size: 12px; font-family: {FONT_FAMILY};")

        # Button styles & Heroicons
        self.btn_ctrl.setIcon(heroicon(HEROICONS["cog"], t["btn_sec_text"], size=16))
        self.btn_ctrl.setStyleSheet(f"""
            QPushButton {{
                background-color: {t['btn_sec_bg']};
                color: {t['btn_sec_text']};
                border: 1px solid {t['btn_sec_border']};
                border-radius: 6px;
                padding: 6px 12px;
                font-size: 12px;
                font-weight: 600;
                font-family: {FONT_FAMILY};
            }}
            QPushButton:hover {{
                background-color: {t['btn_sec_hover']};
            }}
        """)

        self.btn_rdp.setIcon(heroicon(HEROICONS["desktop"], t["btn_pri_text"], size=16))
        self.btn_rdp.setStyleSheet(f"""
            QPushButton {{
                background-color: {t['btn_pri_bg']};
                color: {t['btn_pri_text']};
                border: none;
                border-radius: 6px;
                padding: 6px 12px;
                font-size: 12px;
                font-weight: 600;
                font-family: {FONT_FAMILY};
            }}
            QPushButton:hover {{
                background-color: {t['btn_pri_hover']};
            }}
        """)

        # Bars color update
        self._update_bar_style(self.cpu_bar, self.cpu_bar.value(), t)
        self._update_bar_style(self.ram_bar, self.ram_bar.value(), t)
        self._update_bar_style(self.disk_bar, self.disk_bar.value(), t)
        if self.gpu_bar.isVisible():
            self._update_bar_style(self.gpu_bar, self.gpu_bar.value(), t)

    def open_rdp(self):
        host_ip = self.host['ip']
        subprocess.Popen(['mstsc', f'/v:{host_ip}'])

    def show_menu(self):
        t = self.main_win.current_theme
        menu = QMenu(self)
        menu_css = self.main_win.get_menu_stylesheet()
        menu.setStyleSheet(menu_css)
        menu.addAction(heroicon(HEROICONS["power"], "#ef4444", 16), "Tắt máy", lambda: self.main_win.send_control(self.host, "shutdown"))
        menu.addAction(heroicon(HEROICONS["arrow_path"], t["text_primary"], 16), "Khởi động lại", lambda: self.main_win.send_control(self.host, "reboot"))
        menu.addAction(heroicon(HEROICONS["moon"], t["text_primary"], 16), "Sleep", lambda: self.main_win.send_control(self.host, "sleep"))
        
        menu.addSeparator()

        # 1. Menu Chạy ứng dụng
        app_menu = menu.addMenu(heroicon(HEROICONS["play"], t["text_primary"], 16), "Chạy ứng dụng")
        app_menu.setStyleSheet(menu_css)
        apps = self.main_win.cfg.get("apps", {})
        for name, path in apps.items():
            app_menu.addAction(name, lambda p=path: self.main_win.send_control(self.host, "run_app", app_path=p))
        app_menu.addSeparator()
        custom_run_app = app_menu.addAction(heroicon(HEROICONS["plus"], t["text_primary"], 14), "Khác (nhập mới)...")
        manage_apps = app_menu.addAction(heroicon(HEROICONS["cog"], t["text_primary"], 14), "Quản lý ứng dụng (Sửa/Xóa)...")

        # 2. Menu Mở đường link
        link_menu = menu.addMenu(heroicon(HEROICONS["globe"], t["text_primary"], 16), "Mở đường link (URL)")
        link_menu.setStyleSheet(menu_css)
        links = self.main_win.cfg.get("links", {})
        for name, url in links.items():
            link_menu.addAction(name, lambda u=url: self.main_win.send_control(self.host, "open_url", url=u))
        link_menu.addSeparator()
        custom_run_link = link_menu.addAction(heroicon(HEROICONS["plus"], t["text_primary"], 14), "Khác (nhập mới)...")
        manage_links = link_menu.addAction(heroicon(HEROICONS["cog"], t["text_primary"], 14), "Quản lý đường link (Sửa/Xóa)...")

        menu.addSeparator()
        act_del = menu.addAction(heroicon(HEROICONS["trash"], "#ef4444", 16), "Xóa máy này")
        
        action = menu.exec(QCursor.pos())
        if action == custom_run_app:
            dlg = ItemEditDialog(self, mode="app", title=f"Chạy ứng dụng trên [{self.host.get('name')}]", show_save_checkbox=True)
            if dlg.exec():
                name, path, should_save = dlg.get_data()
                self.main_win.send_control(self.host, "run_app", app_path=path)
                if should_save:
                    self.main_win.cfg.setdefault("apps", {})[name] = path
                    save_config(self.main_win.cfg)
        elif action == manage_apps:
            dlg = AppAndLinkManagerDialog(self.main_win, initial_tab=0, parent=self)
            dlg.exec()
        elif action == custom_run_link:
            dlg = ItemEditDialog(self, mode="link", title=f"Mở đường link trên [{self.host.get('name')}]", show_save_checkbox=True)
            if dlg.exec():
                name, url, should_save = dlg.get_data()
                self.main_win.send_control(self.host, "open_url", url=url)
                if should_save:
                    self.main_win.cfg.setdefault("links", {})[name] = url
                    save_config(self.main_win.cfg)
        elif action == manage_links:
            dlg = AppAndLinkManagerDialog(self.main_win, initial_tab=1, parent=self)
            dlg.exec()
        elif action == act_del:
            self.main_win.delete_host(self.idx)

    def update_values(self, data, error):
        t = self.main_win.current_theme
        was_online = self.is_online
        if data:
            self.is_online = True
            
            # CPU
            cpu = int(data.get("cpu_percent", 0))
            self.cpu_lbl.setText(f"{cpu}%")
            self.cpu_bar.setValue(cpu)
            self._update_bar_style(self.cpu_bar, cpu, t)
            
            # RAM
            ram = int(data.get("ram_percent", 0))
            used_gb = data.get("ram_used_gb", 0)
            total_gb = data.get("ram_total_gb", 0)
            self.ram_lbl.setText(f"{ram}% ({used_gb}/{total_gb} GB)")
            self.ram_bar.setValue(ram)
            self._update_bar_style(self.ram_bar, ram, t)
            
            # DISK
            disk = int(data.get("disk_percent", 0))
            free_gb = data.get("disk_free_gb", 0)
            self.disk_lbl.setText(f"{disk}% (Trống {free_gb} GB)")
            self.disk_bar.setValue(disk)
            self._update_bar_style(self.disk_bar, disk, t)
            
            # GPU (nếu có NVIDIA GPU)
            gpus = data.get("gpu", [])
            if gpus and len(gpus) > 0:
                gpu0 = gpus[0]
                gpu_util = int(gpu0.get("util") or 0)
                gpu_temp = gpu0.get("temp_c")
                temp_str = f" | {int(gpu_temp)}°C" if gpu_temp is not None else ""
                self.gpu_lbl.setText(f"{gpu_util}%{temp_str}")
                self.gpu_bar.setValue(gpu_util)
                self._update_bar_style(self.gpu_bar, gpu_util, t)
                self.gpu_row.show()
            else:
                self.gpu_row.hide()
            
            # Network & Uptime
            down = fmt_rate(data.get("download_bps"))
            up = fmt_rate(data.get("upload_bps"))
            self.net_lbl.setText(f"↓ {down}   ↑ {up}")
            
            upt = fmt_uptime(data.get("uptime_sec"))
            self.uptime_lbl.setText(f"⏱ {upt}" if upt else "")
        else:
            self.is_online = False
            self.net_lbl.setText(f"Offline: {error}")
            self.uptime_lbl.setText("")
            self.gpu_row.hide()

            # Thông báo khi máy bị mất kết nối đột ngột
            if was_online is True and self.main_win.cfg.get("notify_offline", True):
                if hasattr(self.main_win, "tray_icon") and self.main_win.tray_icon:
                    hname = self.host.get("name") or self.host.get("ip", "Máy tính")
                    self.main_win.tray_icon.showMessage(
                        "Cảnh báo: Máy mất kết nối",
                        f"Máy '{hname}' ({self.host.get('ip')}) vừa bị ngắt kết nối!",
                        QSystemTrayIcon.Warning,
                        3500
                    )

        self.apply_theme(t)

# ---------- Các thành phần Chế độ Siêu Thu Nhỏ (Minimal Widget Components) ----------
class RingGaugeWidget(QWidget):
    """Vòng tròn tiến trình siêu nhỏ gọn với font phần trăm to rõ ràng (bỏ chữ CPU/RAM)."""
    def __init__(self, title="CPU", parent=None):
        super().__init__(parent)
        self.title = title
        self.value = 0
        self.setFixedSize(38, 38)
        self.track_color = QColor(148, 163, 184, 45)
        self.color_normal = QColor("#38bdf8") if title == "CPU" else QColor("#10b981")
        self.color_warn = QColor("#fbbf24")
        self.color_danger = QColor("#f87171")
        self.text_color = QColor("#f8fafc")

    def set_value(self, val):
        self.value = max(0, min(100, int(val or 0)))
        self.setToolTip(f"{self.title}: {self.value}%")
        self.update()

    def set_colors(self, text_color, t=None):
        self.text_color = QColor(text_color)
        is_dark = True if not t else (t.get("name", "dark") == "dark")
        self.track_color = QColor(255, 255, 255, 30) if is_dark else QColor(0, 0, 0, 25)
        if self.title == "CPU":
            self.color_normal = QColor("#38bdf8") if is_dark else QColor("#0284c7")
        else:
            self.color_normal = QColor("#34d399") if is_dark else QColor("#059669")
        self.color_warn = QColor("#fbbf24") if is_dark else QColor("#d97706")
        self.color_danger = QColor("#f87171") if is_dark else QColor("#dc2626")
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.TextAntialiasing)
        rect = self.rect().adjusted(2, 2, -2, -2)

        # Đường ray mờ
        pen_track = QPen(self.track_color, 2.8, Qt.SolidLine, Qt.RoundCap)
        p.setPen(pen_track)
        p.drawArc(rect, 0, 360 * 16)

        # Màu theo ngưỡng tải
        if self.value >= 85:
            arc_color = self.color_danger
        elif self.value >= 70:
            arc_color = self.color_warn
        else:
            arc_color = self.color_normal

        # Vòng cung tiến trình
        if self.value > 0:
            pen_val = QPen(arc_color, 2.8, Qt.SolidLine, Qt.RoundCap)
            p.setPen(pen_val)
            span_angle = -int(360 * 16 * (self.value / 100.0))
            p.drawArc(rect, 90 * 16, span_angle)

        # Số phần trăm ở chính giữa vòng tròn (Bỏ chữ CPU/RAM để tăng kích cỡ font tối đa)
        font_size = 7.5 if self.value >= 100 else 9.0
        font_val = QFont(FONT_FAMILY, font_size, QFont.Bold)
        p.setFont(font_val)

        if self.value >= 70:
            p.setPen(arc_color)
        else:
            p.setPen(self.text_color)

        p.drawText(self.rect(), Qt.AlignCenter, f"{self.value}%")
        p.end()

class ConcentricRingWidget(QWidget):
    """Vòng kép đồng tâm: Vòng ngoài CPU, vòng trong RAM, kèm nhãn số chi tiết cả 2 chỉ số."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.cpu = 0
        self.ram = 0
        self.setFixedSize(92, 38)
        self.track_color = QColor(148, 163, 184, 45)
        self.c_cpu = QColor("#38bdf8")
        self.c_ram = QColor("#34d399")
        self.text_color = QColor("#f8fafc")
        self.warn_color = QColor("#fbbf24")
        self.danger_color = QColor("#f87171")

    def set_values(self, cpu, ram):
        self.cpu = max(0, min(100, int(cpu or 0)))
        self.ram = max(0, min(100, int(ram or 0)))
        self.setToolTip(f"CPU: {self.cpu}% | RAM: {self.ram}%")
        self.update()

    def set_colors(self, text_color, t=None):
        self.text_color = QColor(text_color)
        is_dark = True if not t else (t.get("name", "dark") == "dark")
        self.track_color = QColor(255, 255, 255, 30) if is_dark else QColor(0, 0, 0, 25)
        self.c_cpu = QColor("#38bdf8") if is_dark else QColor("#0284c7")
        self.c_ram = QColor("#34d399") if is_dark else QColor("#059669")
        self.warn_color = QColor("#fbbf24") if is_dark else QColor("#d97706")
        self.danger_color = QColor("#f87171") if is_dark else QColor("#dc2626")
        self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.TextAntialiasing)

        # Màu sắc CPU theo ngưỡng
        col_cpu = self.danger_color if self.cpu >= 85 else (self.warn_color if self.cpu >= 70 else self.c_cpu)
        # Màu sắc RAM theo ngưỡng
        col_ram = self.danger_color if self.ram >= 85 else (self.warn_color if self.ram >= 70 else self.c_ram)

        # 1. Vòng ngoài: CPU (Rect 3, 3, 32, 32)
        rect_outer = QRect(3, 3, 32, 32)
        p.setPen(QPen(self.track_color, 2.6, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect_outer, 0, 360 * 16)
        if self.cpu > 0:
            p.setPen(QPen(col_cpu, 2.6, Qt.SolidLine, Qt.RoundCap))
            p.drawArc(rect_outer, 90 * 16, -int(360 * 16 * (self.cpu / 100.0)))

        # 2. Vòng trong: RAM (Rect 8, 8, 22, 22)
        rect_inner = QRect(8, 8, 22, 22)
        p.setPen(QPen(self.track_color, 2.4, Qt.SolidLine, Qt.RoundCap))
        p.drawArc(rect_inner, 0, 360 * 16)
        if self.ram > 0:
            p.setPen(QPen(col_ram, 2.4, Qt.SolidLine, Qt.RoundCap))
            p.drawArc(rect_inner, 90 * 16, -int(360 * 16 * (self.ram / 100.0)))

        # 3. Nhãn hiển thị cả 2 chỉ số bên phải với font to hơn
        font = QFont(FONT_FAMILY, 8, QFont.Bold)
        p.setFont(font)

        # Dòng trên: CPU
        p.setPen(col_cpu)
        p.drawText(QRect(40, 3, 50, 16), Qt.AlignLeft | Qt.AlignVCenter, f"C: {self.cpu}%")

        # Dòng dưới: RAM
        p.setPen(col_ram)
        p.drawText(QRect(40, 19, 50, 16), Qt.AlignLeft | Qt.AlignVCenter, f"R: {self.ram}%")
        p.end()

class MicroBarsWidget(QWidget):
    """Hai thanh ngang siêu mảnh: CPU & RAM với độ rộng tối ưu không bị che khuất."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.cpu = 0
        self.ram = 0
        self.setFixedWidth(104)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 1, 0, 1)
        layout.setSpacing(2)

        # Dòng CPU
        r1 = QHBoxLayout()
        r1.setSpacing(4)
        self.lbl_c = QLabel("C")
        self.lbl_c.setStyleSheet("font-size: 11px; font-weight: 700;")
        self.lbl_c.setFixedWidth(14)
        self.bar_c = QProgressBar()
        self.bar_c.setFixedHeight(5)
        self.bar_c.setTextVisible(False)
        self.bar_c.setRange(0, 100)
        self.val_c = QLabel("0%")
        self.val_c.setStyleSheet("font-size: 11px; font-weight: 700;")
        self.val_c.setFixedWidth(36)
        self.val_c.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        r1.addWidget(self.lbl_c)
        r1.addWidget(self.bar_c)
        r1.addWidget(self.val_c)
        layout.addLayout(r1)

        # Dòng RAM
        r2 = QHBoxLayout()
        r2.setSpacing(4)
        self.lbl_r = QLabel("R")
        self.lbl_r.setStyleSheet("font-size: 11px; font-weight: 700;")
        self.lbl_r.setFixedWidth(14)
        self.bar_r = QProgressBar()
        self.bar_r.setFixedHeight(5)
        self.bar_r.setTextVisible(False)
        self.bar_r.setRange(0, 100)
        self.val_r = QLabel("0%")
        self.val_r.setStyleSheet("font-size: 11px; font-weight: 700;")
        self.val_r.setFixedWidth(36)
        self.val_r.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        r2.addWidget(self.lbl_r)
        r2.addWidget(self.bar_r)
        r2.addWidget(self.val_r)
        layout.addLayout(r2)

    def set_values(self, cpu, ram, t=None):
        self.cpu = max(0, min(100, int(cpu or 0)))
        self.ram = max(0, min(100, int(ram or 0)))
        self.val_c.setText(f"{self.cpu}%")
        self.bar_c.setValue(self.cpu)
        self.val_r.setText(f"{self.ram}%")
        self.bar_r.setValue(self.ram)

        is_dark = True if not t else (t.get("name", "dark") == "dark")
        c_normal = "#38bdf8" if is_dark else "#0284c7"
        r_normal = "#34d399" if is_dark else "#059669"
        val_color = "#ffffff" if is_dark else "#0f172a"
        bar_bg = "rgba(255, 255, 255, 0.16)" if is_dark else "rgba(0, 0, 0, 0.08)"

        c_chunk = (t["bar_danger"] if t else "#f87171") if self.cpu >= 85 else ((t["bar_warn"] if t else "#fbbf24") if self.cpu >= 70 else c_normal)
        r_chunk = (t["bar_danger"] if t else "#f87171") if self.ram >= 85 else ((t["bar_warn"] if t else "#fbbf24") if self.ram >= 70 else r_normal)

        self.bar_c.setStyleSheet(f"""
            QProgressBar {{ background-color: {bar_bg}; border-radius: 2.5px; border: none; }}
            QProgressBar::chunk {{ background-color: {c_chunk}; border-radius: 2.5px; }}
        """)
        self.bar_r.setStyleSheet(f"""
            QProgressBar {{ background-color: {bar_bg}; border-radius: 2.5px; border: none; }}
            QProgressBar::chunk {{ background-color: {r_chunk}; border-radius: 2.5px; }}
        """)

        self.lbl_c.setStyleSheet(f"font-size: 11px; font-weight: 700; color: {c_chunk};")
        self.lbl_r.setStyleSheet(f"font-size: 11px; font-weight: 700; color: {r_chunk};")
        self.val_c.setStyleSheet(f"font-size: 11px; font-weight: 700; color: {val_color};")
        self.val_r.setStyleSheet(f"font-size: 11px; font-weight: 700; color: {val_color};")

class DigitalPillWidget(QWidget):
    """Thẻ số điện tử HUD: C: 38% | R: 62% hiển thị tương phản cao trong mọi theme."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedWidth(106)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        self.pill_cpu = QLabel("C: 0%")
        self.pill_cpu.setAlignment(Qt.AlignCenter)
        self.pill_ram = QLabel("R: 0%")
        self.pill_ram.setAlignment(Qt.AlignCenter)
        layout.addWidget(self.pill_cpu)
        layout.addWidget(self.pill_ram)

    def set_values(self, cpu, ram, t=None):
        c = max(0, min(100, int(cpu or 0)))
        r = max(0, min(100, int(ram or 0)))
        is_dark = True if not t else (t.get("name", "dark") == "dark")

        c_normal = "#38bdf8" if is_dark else "#0284c7"
        r_normal = "#34d399" if is_dark else "#059669"
        bg_c = "rgba(56, 189, 248, 0.18)" if is_dark else "rgba(2, 132, 199, 0.12)"
        bg_r = "rgba(52, 211, 153, 0.18)" if is_dark else "rgba(5, 150, 105, 0.12)"

        c_color = (t["bar_danger"] if t else "#f87171") if c >= 85 else ((t["bar_warn"] if t else "#fbbf24") if c >= 70 else c_normal)
        r_color = (t["bar_danger"] if t else "#f87171") if r >= 85 else ((t["bar_warn"] if t else "#fbbf24") if r >= 70 else r_normal)

        self.pill_cpu.setText(f"C: {c}%")
        self.pill_cpu.setStyleSheet(f"background: {bg_c}; color: {c_color}; border: 1px solid {c_color}; padding: 2px 7px; border-radius: 5px; font-size: 11.5px; font-weight: 700;")

        self.pill_ram.setText(f"R: {r}%")
        self.pill_ram.setStyleSheet(f"background: {bg_r}; color: {r_color}; border: 1px solid {r_color}; padding: 2px 7px; border-radius: 5px; font-size: 11.5px; font-weight: 700;")

class MinimalHostItem(QFrame):
    """Khung thẻ siêu thu nhỏ của từng máy trong Minimal Mode."""
    def __init__(self, idx, host, main_win):
        super().__init__()
        self.idx, self.host, self.main_win = idx, host, main_win
        self.is_online = None
        self.cpu = 0
        self.ram = 0

        self.item_layout = QHBoxLayout(self)
        self.item_layout.setContentsMargins(0, 0, 0, 0)
        self.item_layout.setSpacing(6)

        # Đèn LED trạng thái
        self.status_dot = QWidget()
        self.status_dot.setFixedSize(8, 8)
        self.item_layout.addWidget(self.status_dot, 0, Qt.AlignVCenter)

        # Tên máy
        self.name_lbl = QLabel(host.get("name", "PC"))
        self.name_lbl.setAlignment(Qt.AlignVCenter | Qt.AlignLeft)
        self.item_layout.addWidget(self.name_lbl, 0, Qt.AlignVCenter)

        # Spacer giãn nở ở giữa để đẩy cụm chỉ số sang sát mép phải, thẳng hàng tuyệt đối theo cột
        self.item_layout.addStretch()

        # Metric Stack (chuyển đổi tức thời giữa 4 kiểu và trạng thái Offline)
        self.metric_stack = QStackedWidget()
        self.metric_stack.setFixedWidth(80)

        # Page 0: Twin Rings (Kiểu 1 - Mặc định)
        self.page_twin = QWidget()
        self.page_twin.setFixedWidth(80)
        twin_layout = QHBoxLayout(self.page_twin)
        twin_layout.setContentsMargins(0, 0, 0, 0)
        twin_layout.setSpacing(4)
        self.ring_cpu = RingGaugeWidget("CPU")
        self.ring_ram = RingGaugeWidget("RAM")
        twin_layout.addWidget(self.ring_cpu)
        twin_layout.addWidget(self.ring_ram)
        self.metric_stack.addWidget(self.page_twin)  # Index 0

        # Page 1: Concentric Rings (Kiểu 2)
        self.ring_concentric = ConcentricRingWidget()
        self.metric_stack.addWidget(self.ring_concentric)  # Index 1

        # Page 2: Micro Bars (Kiểu 3)
        self.micro_bars = MicroBarsWidget()
        self.metric_stack.addWidget(self.micro_bars)  # Index 2

        # Page 3: Digital Pill (Kiểu 4)
        self.digital_pill = DigitalPillWidget()
        self.metric_stack.addWidget(self.digital_pill)  # Index 3

        # Page 4: Offline Badge
        self.offline_lbl = QLabel("Offline")
        self.offline_lbl.setAlignment(Qt.AlignCenter)
        self.metric_stack.addWidget(self.offline_lbl)  # Index 4

        self.item_layout.addWidget(self.metric_stack, 0, Qt.AlignVCenter)

        self.apply_theme(self.main_win.current_theme)
        self.set_style(self.main_win.minimal_style)

    def set_style(self, style_name):
        if style_name == "concentric_rings":
            metric_w = 92
            idx = 1
        elif style_name == "micro_bars":
            metric_w = 104
            idx = 2
        elif style_name == "digital_pill":
            metric_w = 106
            idx = 3
        else: # twin_rings
            metric_w = 80
            idx = 0

        self.metric_stack.setFixedWidth(metric_w)
        if self.is_online is False:
            self.metric_stack.setCurrentIndex(4)
        else:
            self.metric_stack.setCurrentIndex(idx)

    def update_values(self, data, error):
        t = self.main_win.current_theme
        if data:
            self.is_online = True
            self.cpu = int(data.get("cpu_percent", 0))
            self.ram = int(data.get("ram_percent", 0))

            self.ring_cpu.set_value(self.cpu)
            self.ring_ram.set_value(self.ram)
            self.ring_concentric.set_values(self.cpu, self.ram)
            self.micro_bars.set_values(self.cpu, self.ram, t)
            self.digital_pill.set_values(self.cpu, self.ram, t)

            self.set_style(self.main_win.minimal_style)
        else:
            self.is_online = False
            self.metric_stack.setCurrentIndex(4)

        self.apply_theme(t)

    def apply_theme(self, t):
        is_dark = self.main_win.theme_name == "dark"
        text_color = "#ffffff" if is_dark else "#0f172a"

        self.setStyleSheet("""
            MinimalHostItem {
                background: transparent;
                background-color: transparent;
                border: none;
            }
            MinimalHostItem:hover {
                background: transparent;
                background-color: transparent;
                border: none;
            }
        """)
        self.name_lbl.setStyleSheet(f"color: {text_color}; font-weight: 600; font-size: 12.5px; font-family: {FONT_FAMILY};")
        
        status_color = "#10b981" if self.is_online is True else ("#ef4444" if self.is_online is False else "#64748b")
        self.status_dot.setStyleSheet(f"background-color: {status_color}; border-radius: 4px;")

        self.ring_cpu.set_colors(text_color, t)
        self.ring_ram.set_colors(text_color, t)
        self.ring_concentric.set_colors(text_color, t)
        self.micro_bars.set_values(self.cpu, self.ram, t)
        self.digital_pill.set_values(self.cpu, self.ram, t)

        if is_dark:
            self.offline_lbl.setStyleSheet("color: #f87171; font-size: 11px; font-weight: 700; padding: 2px 8px; background: rgba(239, 68, 68, 0.2); border: 1px solid rgba(239, 68, 68, 0.4); border-radius: 6px;")
        else:
            self.offline_lbl.setStyleSheet("color: #dc2626; font-size: 11px; font-weight: 700; padding: 2px 8px; background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.3); border-radius: 6px;")

    def open_rdp(self):
        host_ip = self.host['ip']
        subprocess.Popen(['mstsc', f'/v:{host_ip}'])

    def show_context_menu(self, global_pos):
        t = self.main_win.current_theme
        is_dark = self.main_win.theme_name == "dark"
        menu = QMenu(self)
        menu_css = self.main_win.get_menu_stylesheet()
        menu.setStyleSheet(menu_css)

        title_act = menu.addAction(f"💻 {self.host.get('name', 'PC')}")
        title_act.setEnabled(False)
        menu.addSeparator()

        menu.addAction(heroicon(HEROICONS["desktop"], t["text_primary"], 16), "Kết nối RDP", self.open_rdp)

        ctrl_menu = menu.addMenu(heroicon(HEROICONS["cog"], t["text_primary"], 16), "Điều khiển máy")
        ctrl_menu.setStyleSheet(menu_css)
        ctrl_menu.addAction(heroicon(HEROICONS["power"], "#ef4444", 16), "Tắt máy", lambda: self.main_win.send_control(self.host, "shutdown"))
        ctrl_menu.addAction(heroicon(HEROICONS["arrow_path"], t["text_primary"], 16), "Khởi động lại", lambda: self.main_win.send_control(self.host, "reboot"))
        ctrl_menu.addAction(heroicon(HEROICONS["moon"], t["text_primary"], 16), "Sleep", lambda: self.main_win.send_control(self.host, "sleep"))
        ctrl_menu.addSeparator()

        app_menu = ctrl_menu.addMenu(heroicon(HEROICONS["play"], t["text_primary"], 16), "Chạy ứng dụng")
        app_menu.setStyleSheet(menu_css)
        for name, path in self.main_win.cfg.get("apps", {}).items():
            app_menu.addAction(name, lambda p=path: self.main_win.send_control(self.host, "run_app", app_path=p))

        link_menu = ctrl_menu.addMenu(heroicon(HEROICONS["globe"], t["text_primary"], 16), "Mở đường link (URL)")
        link_menu.setStyleSheet(menu_css)
        for name, url in self.main_win.cfg.get("links", {}).items():
            link_menu.addAction(name, lambda u=url: self.main_win.send_control(self.host, "open_url", url=u))

        menu.addSeparator()

        # Chuyển đổi giao diện Sáng / Tối
        theme_icon = heroicon(HEROICONS["sun" if is_dark else "moon"], t["text_primary"], 16)
        theme_text = "Chuyển sang Chế độ sáng" if is_dark else "Chuyển sang Chế độ tối"
        menu.addAction(theme_icon, theme_text, self.main_win.toggle_theme)

        # Kiểu hiển thị Siêu Thu Nhỏ
        style_menu = menu.addMenu(heroicon(HEROICONS["swatch"], t["text_primary"], 16), "Kiểu hiển thị Siêu Thu Nhỏ")
        style_menu.setStyleSheet(menu_css)
        a1 = style_menu.addAction("Kiểu 1: Vòng tròn đôi (Twin Rings - Mặc định)", lambda: self.main_win.set_minimal_style("twin_rings"))
        a1.setCheckable(True)
        a1.setChecked(self.main_win.minimal_style == "twin_rings")

        a2 = style_menu.addAction("Kiểu 2: Vòng kép đồng tâm (Concentric Rings)", lambda: self.main_win.set_minimal_style("concentric_rings"))
        a2.setCheckable(True)
        a2.setChecked(self.main_win.minimal_style == "concentric_rings")

        a3 = style_menu.addAction("Kiểu 3: Thanh tiến trình mini (Micro Bars)", lambda: self.main_win.set_minimal_style("micro_bars"))
        a3.setCheckable(True)
        a3.setChecked(self.main_win.minimal_style == "micro_bars")

        a4 = style_menu.addAction("Kiểu 4: Thẻ số điện tử HUD (Digital Pill)", lambda: self.main_win.set_minimal_style("digital_pill"))
        a4.setCheckable(True)
        a4.setChecked(self.main_win.minimal_style == "digital_pill")

        layout_menu = menu.addMenu(heroicon(HEROICONS["squares"], t["text_primary"], 16), "Bố cục khung")
        layout_menu.setStyleSheet(menu_css)
        l1 = layout_menu.addAction("Khung dọc (Vertical Dock)", lambda: self.main_win.set_minimal_layout("vertical"))
        l1.setCheckable(True)
        l1.setChecked(self.main_win.minimal_layout == "vertical")

        l2 = layout_menu.addAction("Thanh ngang (Horizontal Bar)", lambda: self.main_win.set_minimal_layout("horizontal"))
        l2.setCheckable(True)
        l2.setChecked(self.main_win.minimal_layout == "horizontal")

        menu.addSeparator()
        menu.addAction(heroicon(HEROICONS["fit"], t["text_primary"], 16), "Quay lại Bảng Điều Khiển đầy đủ (F9)", self.main_win.toggle_minimal_mode)
        menu.addAction(heroicon(HEROICONS["close"], "#ef4444", 16), "Ẩn xuống khay hệ thống (Esc)", self.main_win.close)

        menu.exec(global_pos)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.main_win._drag_pos = event.globalPosition().toPoint() - self.main_win.frameGeometry().topLeft()
            self.main_win._is_dragging = True
            event.accept()
        elif event.button() == Qt.RightButton:
            self.show_context_menu(event.globalPosition().toPoint())
            event.accept()
        else:
            super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if event.buttons() & Qt.LeftButton and hasattr(self.main_win, '_drag_pos') and self.main_win._drag_pos:
            self.main_win.move(event.globalPosition().toPoint() - self.main_win._drag_pos)
            event.accept()
        else:
            super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.main_win._is_dragging = False
            event.accept()
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event):
        # Không tự ý phóng to khi nhấp đúp vào bong bóng
        event.accept()

# ---------- Cửa sổ chính ----------
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.cfg = load_config()
        self.cards = {}
        self.last_visible_count = -1
        self.user_manually_resized = False
        self.is_floating = False
        self.is_minimal = False
        self.minimal_style = self.cfg.get("minimal_style", "twin_rings")
        self.minimal_layout = self.cfg.get("minimal_layout", "vertical")
        self.minimal_items = {}
        self.normal_geometry = None
        self.threadpool = QThreadPool.globalInstance()
        self.setWindowTitle(APP_TITLE)
        self.setWindowIcon(get_dashboard_icon())
        self.has_notified_tray = False
        
        # Theme setup
        self.theme_name = self.cfg.get("theme", "dark")
        self.current_theme = THEMES.get(self.theme_name, THEMES["dark"])

        # Kích thước tối thiểu và kích thước thích ứng ban đầu
        self.setMinimumSize(320, 160)
        screen = QGuiApplication.primaryScreen().availableGeometry()
        init_w = min(400, screen.width() - 40)
        init_h = min(560, screen.height() - 80)
        self.resize(init_w, init_h)

        # Biến điều khiển kéo di chuyển và co dãn cửa sổ nổi
        self._resizing = False
        self._resize_edge = None
        self._press_pos = None
        self._press_geo = None
        self._drag_pos = None
        self._is_dragging = False
        self.setMouseTracking(True)

        # Thanh Mini Header dành riêng cho chế độ nổi (mặc định ẩn)
        self.mini_header = QWidget()
        mini_layout = QHBoxLayout(self.mini_header)
        mini_layout.setContentsMargins(10, 4, 10, 4)
        mini_layout.setSpacing(6)
        
        self.mini_title = QLabel("LAN Monitor • Nổi")
        self.mini_title.setStyleSheet("font-size: 11px; font-weight: 600;")
        mini_layout.addWidget(self.mini_title)
        mini_layout.addStretch()
        
        # Nút thu phóng về chế độ đầy đủ
        self.btn_exit_float = QToolButton()
        self.btn_exit_float.setToolTip("Quay lại giao diện đầy đủ (F11)")
        self.btn_exit_float.clicked.connect(self.toggle_floating_mode)
        mini_layout.addWidget(self.btn_exit_float)

        # Nút đóng nhanh app
        self.btn_close_app = QToolButton()
        self.btn_close_app.setToolTip("Đóng ứng dụng")
        self.btn_close_app.clicked.connect(self.close)
        mini_layout.addWidget(self.btn_close_app)
        
        self.mini_header.hide()
        self.mini_header.mousePressEvent = self.mousePressEvent
        self.mini_header.mouseMoveEvent = self.mouseMoveEvent
        self.mini_header.mouseReleaseEvent = self.mouseReleaseEvent

        # Thanh công cụ trên cùng (Chế độ đầy đủ)
        self.toolbar = self.addToolBar("Main")
        self.toolbar.setMovable(False)
        self.toolbar.setFloatable(False)

        # Tiêu đề app bên trái
        self.brand_lbl = QLabel(" LAN Monitor")
        self.brand_lbl.setStyleSheet(f"font-weight: 600; font-size: 14px; padding-left: 4px; font-family: {FONT_FAMILY};")
        self.toolbar.addWidget(self.brand_lbl)

        # Khoảng trống giãn nở
        spacer = QWidget()
        spacer.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        self.toolbar.addWidget(spacer)

        # Nút 1: Thêm máy (Heroicon plus)
        self.btn_add = QToolButton()
        self.btn_add.setText(" Thêm máy")
        self.btn_add.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.btn_add.clicked.connect(self.add_host)
        self.toolbar.addWidget(self.btn_add)

        # Nút 2: Menu chức năng Dropdown (Heroicon bars_3)
        self.btn_menu = QToolButton()
        self.btn_menu.setText(" Menu")
        self.btn_menu.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.btn_menu.setPopupMode(QToolButton.InstantPopup)
        
        # Menu Dropdown chứa tất cả các chức năng thu gọn
        self.options_menu = QMenu(self)
        
        self.floating_act = self.options_menu.addAction("Cửa sổ nổi (F11)", self.toggle_floating_mode)
        self.floating_act.setCheckable(True)

        self.minimal_act = self.options_menu.addAction("Chế độ Siêu Thu Nhỏ (F9)", self.toggle_minimal_mode)
        self.minimal_act.setCheckable(True)

        # Submenu Kiểu Siêu Thu Nhỏ (Minimal Style)
        self.menu_min_style = self.options_menu.addMenu("Kiểu Siêu Thu Nhỏ (Style)")
        self.act_style_twin = self.menu_min_style.addAction("Kiểu 1: Vòng tròn đôi (Twin Rings - Mặc định)", lambda: self.set_minimal_style("twin_rings"))
        self.act_style_twin.setCheckable(True)
        self.act_style_concentric = self.menu_min_style.addAction("Kiểu 2: Vòng kép đồng tâm (Concentric)", lambda: self.set_minimal_style("concentric_rings"))
        self.act_style_concentric.setCheckable(True)
        self.act_style_bars = self.menu_min_style.addAction("Kiểu 3: Thanh tiến trình mini (Micro Bars)", lambda: self.set_minimal_style("micro_bars"))
        self.act_style_bars.setCheckable(True)
        self.act_style_pill = self.menu_min_style.addAction("Kiểu 4: Thẻ số điện tử HUD (Digital Pill)", lambda: self.set_minimal_style("digital_pill"))
        self.act_style_pill.setCheckable(True)

        # Submenu Bố cục Siêu Thu Nhỏ (Layout)
        self.menu_min_layout = self.options_menu.addMenu("Bố cục Siêu Thu Nhỏ (Layout)")
        self.act_layout_vert = self.menu_min_layout.addAction("Khung dọc (Vertical Dock)", lambda: self.set_minimal_layout("vertical"))
        self.act_layout_vert.setCheckable(True)
        self.act_layout_horiz = self.menu_min_layout.addAction("Thanh ngang (Horizontal Bar)", lambda: self.set_minimal_layout("horizontal"))
        self.act_layout_horiz.setCheckable(True)

        self.hide_offline_act = self.options_menu.addAction("Chỉ hiện máy Online", self.toggle_hide_offline)
        self.hide_offline_act.setCheckable(True)
        self.hide_offline_act.setChecked(self.cfg.get("hide_offline", False))
        
        self.fit_act = self.options_menu.addAction("Thu gọn vừa khung", self.on_fit_clicked)
        
        self.ontop_act = self.options_menu.addAction("Ghim trên cùng", self.toggle_ontop)
        self.ontop_act.setCheckable(True)
        
        self.theme_act = self.options_menu.addAction("Chế độ sáng", self.toggle_theme)
        
        self.options_menu.addSeparator()
        self.manage_apps_act = self.options_menu.addAction("Quản lý Ứng dụng & Link...", lambda: self.open_app_link_manager(0))

        self.options_menu.addSeparator()
        self.open_cfg_act = self.options_menu.addAction("Mở file cấu hình (JSON)...", self.open_config_file)
        self.import_cfg_act = self.options_menu.addAction("Nhập cấu hình từ file khác...", self.import_config_file)

        self.options_menu.addSeparator()
        self.ip_act = self.options_menu.addAction("IP Tailscale", self.show_tailscale_info)
        
        self.options_menu.addSeparator()
        self.autostart_act = self.options_menu.addAction("Khởi động cùng Windows", self.toggle_autostart)
        self.autostart_act.setCheckable(True)
        self.autostart_act.setChecked(is_autostart_enabled())

        self.notify_act = self.options_menu.addAction("Báo động khi máy mất kết nối", self.toggle_notify_offline)
        self.notify_act.setCheckable(True)
        self.notify_act.setChecked(self.cfg.get("notify_offline", True))
        
        self.btn_menu.setMenu(self.options_menu)
        self.toolbar.addWidget(self.btn_menu)
        
        # Scroll Area & Layout
        self.main_wrapper = QWidget()
        self.wrapper_layout = QVBoxLayout(self.main_wrapper)
        self.wrapper_layout.setContentsMargins(0, 0, 0, 0)
        self.wrapper_layout.setSpacing(0)
        self.wrapper_layout.addWidget(self.mini_header)
        
        self.scroll = QScrollArea()
        self.scroll.setObjectName("mainScroll")
        self.scroll.setWidgetResizable(True)
        self.scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.container = QWidget()
        self.layout = QVBoxLayout(self.container)
        self.layout.setAlignment(Qt.AlignTop)
        self.layout.setContentsMargins(10, 10, 10, 10)
        self.layout.setSpacing(8)

        self.empty_lbl = QLabel("Không có máy nào đang Online\n(Chọn Menu -> tắt 'Chỉ hiện máy Online' để xem máy Offline)")
        self.empty_lbl.setAlignment(Qt.AlignCenter)
        self.empty_lbl.setStyleSheet(f"font-size: 13px; padding: 40px 15px; font-family: {FONT_FAMILY};")
        self.layout.addWidget(self.empty_lbl)
        self.empty_lbl.hide()

        self.scroll.setWidget(self.container)
        self.wrapper_layout.addWidget(self.scroll)

        # Chế độ Siêu Thu Nhỏ (Dynamic Island Bong Bóng Nổi - Chuẩn iPhone Pill)
        self.minimal_wrapper = QWidget()
        self.minimal_wrapper.setObjectName("minimalWrapper")
        self.minimal_wrapper_layout = QVBoxLayout(self.minimal_wrapper)
        self.minimal_wrapper_layout.setContentsMargins(12, 2, 12, 2)
        self.minimal_wrapper_layout.setSpacing(0)

        self.minimal_wrapper.mousePressEvent = self.mousePressEvent
        self.minimal_wrapper.mouseMoveEvent = self.mouseMoveEvent
        self.minimal_wrapper.mouseReleaseEvent = self.mouseReleaseEvent
        self.minimal_wrapper.mouseDoubleClickEvent = self.mouseDoubleClickEvent

        # Container chứa danh sách các máy dạng minimal (Trong suốt hoàn toàn, không viền)
        self.minimal_scroll = QScrollArea()
        self.minimal_scroll.setObjectName("minimalScroll")
        self.minimal_scroll.setWidgetResizable(True)
        self.minimal_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.minimal_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.minimal_scroll.setStyleSheet("border: none; background: transparent;")

        self.minimal_container = QWidget()
        self.minimal_container.setObjectName("minimalContainer")
        self.minimal_container.setStyleSheet("border: none; background: transparent;")
        if self.minimal_layout == "horizontal":
            self.minimal_items_layout = QHBoxLayout(self.minimal_container)
            self.minimal_items_layout.setContentsMargins(0, 0, 0, 0)
            self.minimal_items_layout.setSpacing(16)
            self.minimal_items_layout.setAlignment(Qt.AlignCenter)
        else:
            self.minimal_items_layout = QVBoxLayout(self.minimal_container)
            self.minimal_items_layout.setContentsMargins(0, 0, 0, 0)
            self.minimal_items_layout.setSpacing(4)
            self.minimal_items_layout.setAlignment(Qt.AlignTop)

        self.min_empty_lbl = QLabel("Không có máy Online")
        self.min_empty_lbl.setAlignment(Qt.AlignCenter)
        self.min_empty_lbl.setStyleSheet(f"font-size: 11px; padding: 10px; font-family: {FONT_FAMILY}; color: #94a3b8;")
        self.minimal_items_layout.addWidget(self.min_empty_lbl)
        self.min_empty_lbl.hide()

        self.minimal_scroll.setWidget(self.minimal_container)
        self.minimal_wrapper_layout.addWidget(self.minimal_scroll)

        # Root Stacked Widget (Chuyển đổi tức thời giữa Dashboard chuẩn và Minimal Mode)
        self.central_stacked = QStackedWidget()
        self.central_stacked.addWidget(self.main_wrapper)     # Index 0: Chuẩn & Cửa sổ nổi
        self.central_stacked.addWidget(self.minimal_wrapper)  # Index 1: Siêu Thu Nhỏ
        self.setCentralWidget(self.central_stacked)

        # Status Bar
        self.status_lbl = QLabel("Online: 0/0")
        self.status_lbl.setStyleSheet(f"padding-right: 12px; font-weight: 600; font-size: 11px; font-family: {FONT_FAMILY};")
        self.statusBar().addPermanentWidget(self.status_lbl)

        # Phím tắt F11 và Ctrl+M để toggle nhanh chế độ nổi
        self.shortcut_f11 = QShortcut(QKeySequence("F11"), self, self.toggle_floating_mode)
        self.shortcut_ctrl_m = QShortcut(QKeySequence("Ctrl+M"), self, self.toggle_floating_mode)

        # Phím tắt F9 và Ctrl+Shift+M để toggle nhanh chế độ Siêu Thu Nhỏ
        self.shortcut_f9 = QShortcut(QKeySequence("F9"), self, self.toggle_minimal_mode)
        self.shortcut_ctrl_shift_m = QShortcut(QKeySequence("Ctrl+Shift+M"), self, self.toggle_minimal_mode)

        # QSizeGrip để kéo resize ở góc dưới bên phải khi ở chế độ nổi
        self.sizegrip = QSizeGrip(self)
        self.sizegrip.setFixedSize(16, 16)
        self.sizegrip.hide()

        # Áp dụng theme và icon Heroicons
        self.apply_theme()

        self.timer = QTimer()
        self.timer.timeout.connect(self.refresh)
        self.timer.start(REFRESH_MS)
        self.fetch_signals = FetchSignals()
        self.fetch_signals.finished.connect(self.on_finished)
        self.refresh()
        self._setup_system_tray()

    def toggle_floating_mode(self):
        if self.is_minimal:
            self.is_minimal = False
            self.minimal_act.setChecked(False)
            if hasattr(self, "act_tray_minimal") and self.act_tray_minimal:
                self.act_tray_minimal.setChecked(False)
            self.central_stacked.setCurrentIndex(0)

        self.is_floating = not self.is_floating
        self.floating_act.setChecked(self.is_floating)
        if hasattr(self, "act_tray_floating") and self.act_tray_floating:
            self.act_tray_floating.setChecked(self.is_floating)
        cur_pos = self.pos()

        if self.is_floating:
            # Lưu lại kích thước hiện tại
            self.normal_geometry = self.geometry()
            
            # Cho phép thu nhỏ hơn ở chế độ nổi
            self.setMinimumSize(250, 100)

            # Chuyển sang frameless & ghim trên cùng
            self.setWindowFlags(Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
            self.setAttribute(Qt.WA_TranslucentBackground, False)
            self.show()
            self.move(cur_pos)

            # Ẩn toolbar và statusbar, hiện mini header và sizegrip
            self.toolbar.hide()
            self.statusBar().hide()
            self.mini_header.show()
            self.sizegrip.show()
            self.sizegrip.move(self.width() - 16, self.height() - 16)
            self.sizegrip.raise_()

            # Độ mờ 80%
            self.setWindowOpacity(0.80)

            # Báo cho các card thu nhỏ gọn gàng
            for card in self.cards.values():
                card.set_floating_mode(True)

            self.user_manually_resized = False
            self.fit_to_content(force=True)
        else:
            # Thoát chế độ nổi
            self.setMinimumSize(340, 220)
            flags = Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
            if self.ontop_act.isChecked():
                flags |= Qt.WindowStaysOnTopHint
            
            self.setWindowFlags(flags)
            self.show()
            self.move(cur_pos)

            self.toolbar.show()
            self.statusBar().show()
            self.mini_header.hide()
            self.sizegrip.hide()
            self.setCursor(Qt.ArrowCursor)

            # Trở lại độ mờ 100%
            self.setWindowOpacity(1.0)

            for card in self.cards.values():
                card.set_floating_mode(False)

            self.user_manually_resized = False
            self.fit_to_content(force=True)

    def toggle_minimal_mode(self):
        """Bật/tắt chế độ Siêu Thu Nhỏ (Dynamic Island Bong Bóng Nổi) tách biệt hoàn toàn."""
        if self.is_minimal:
            # Thoát chế độ siêu thu nhỏ -> Quay lại giao diện bình thường
            self.is_minimal = False
            self.minimal_act.setChecked(False)
            if hasattr(self, "act_tray_minimal") and self.act_tray_minimal:
                self.act_tray_minimal.setChecked(False)

            cur_pos = self.pos()
            self.central_stacked.setCurrentIndex(0)

            flags = Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
            if self.ontop_act.isChecked():
                flags |= Qt.WindowStaysOnTopHint

            self.setAttribute(Qt.WA_TranslucentBackground, False)
            self.setWindowFlags(flags)
            self.show()
            self.move(cur_pos)

            self.toolbar.show()
            self.statusBar().show()
            self.setCursor(Qt.ArrowCursor)
            self.setWindowOpacity(1.0)

            if self.normal_geometry:
                self.setGeometry(self.normal_geometry)
            else:
                self.setMinimumSize(340, 220)
                self.resize(400, 560)
            self.apply_theme()
            self.fit_to_content(force=True)
        else:
            # Thoát chế độ nổi nếu đang mở
            if self.is_floating:
                self.is_floating = False
                self.floating_act.setChecked(False)
                if hasattr(self, "act_tray_floating") and self.act_tray_floating:
                    self.act_tray_floating.setChecked(False)
                self.mini_header.hide()
                self.sizegrip.hide()
                for card in self.cards.values():
                    card.set_floating_mode(False)

            if not self.normal_geometry:
                self.normal_geometry = self.geometry()

            self.is_minimal = True
            self.minimal_act.setChecked(True)
            if hasattr(self, "act_tray_minimal") and self.act_tray_minimal:
                self.act_tray_minimal.setChecked(True)

            cur_pos = self.pos()
            self.central_stacked.setCurrentIndex(1)

            self.setAttribute(Qt.WA_TranslucentBackground, True)
            self.setWindowFlags(Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
            self.show()
            self.move(cur_pos)

            self.toolbar.hide()
            self.statusBar().hide()
            self.setWindowOpacity(0.94)

            self.apply_minimal_style()
            self.apply_theme()
            self.fit_minimal_size()

    def set_minimal_style(self, new_style):
        self.minimal_style = new_style
        self.cfg["minimal_style"] = new_style
        save_config(self.cfg)
        self.apply_minimal_style()
        if self.is_minimal:
            self.fit_minimal_size()

    def set_minimal_layout(self, new_layout):
        self.minimal_layout = new_layout
        self.cfg["minimal_layout"] = new_layout
        save_config(self.cfg)
        self._rebuild_minimal_layout()
        if self.is_minimal:
            self.fit_minimal_size()

    def apply_minimal_style(self):
        if hasattr(self, "act_style_twin"):
            self.act_style_twin.setChecked(self.minimal_style == "twin_rings")
            self.act_style_concentric.setChecked(self.minimal_style == "concentric_rings")
            self.act_style_bars.setChecked(self.minimal_style == "micro_bars")
            self.act_style_pill.setChecked(self.minimal_style == "digital_pill")
        for item in self.minimal_items.values():
            item.set_style(self.minimal_style)

    def _rebuild_minimal_layout(self):
        if hasattr(self, "act_layout_vert"):
            self.act_layout_vert.setChecked(self.minimal_layout == "vertical")
            self.act_layout_horiz.setChecked(self.minimal_layout == "horizontal")

        old_layout = self.minimal_container.layout()
        if old_layout:
            while old_layout.count() > 0:
                old_layout.takeAt(0)
            QWidget().setLayout(old_layout)

        if self.minimal_layout == "horizontal":
            new_layout = QHBoxLayout(self.minimal_container)
            new_layout.setContentsMargins(0, 0, 0, 0)
            new_layout.setSpacing(16)
            new_layout.setAlignment(Qt.AlignCenter)
        else:
            new_layout = QVBoxLayout(self.minimal_container)
            new_layout.setContentsMargins(0, 0, 0, 0)
            new_layout.setSpacing(4)
            new_layout.setAlignment(Qt.AlignTop)

        self.minimal_items_layout = new_layout
        new_layout.addWidget(self.min_empty_lbl)
        for idx in sorted(self.minimal_items.keys()):
            new_layout.addWidget(self.minimal_items[idx])

    def fit_minimal_size(self):
        visible_items = [item for item in self.minimal_items.values() if not item.isHidden()]
        count = len(visible_items)
        fm = QFontMetrics(QFont(FONT_FAMILY, 12, QFont.Bold))

        # Xác định độ rộng của phần hiển thị chỉ số theo từng kiểu
        if self.minimal_style == "twin_rings":
            metric_w = 80       # 2 vòng 38px + khoảng cách 4px
        elif self.minimal_style == "concentric_rings":
            metric_w = 92       # Vòng kép + nhãn số 2 dòng
        elif self.minimal_style == "micro_bars":
            metric_w = 104      # 2 thanh ngang + % số
        else: # digital_pill
            metric_w = 106      # 2 thẻ số pill

        if count == 0:
            w = 180
            h = 44
            self.setMinimumSize(w, h)
            self.resize(w, h)
            return

        if self.minimal_layout == "horizontal":
            item_widths = []
            for item in visible_items:
                w_t = fm.horizontalAdvance(item.host.get("name", "PC"))
                # status dot(8) + spacing(6) + text + spacing(14) + metric
                item_widths.append(8 + 6 + w_t + 14 + metric_w)
            total_w = sum(item_widths) + max(0, count - 1) * 16 + 24
            w = max(180, total_w)
            h = 44
            self.setMinimumSize(w, h)
            self.resize(w, h)
        else:
            max_name_w = 50
            for item in visible_items:
                w_text = fm.horizontalAdvance(item.host.get("name", "PC"))
                if w_text > max_name_w:
                    max_name_w = w_text
            # status dot(8) + spacing(6) + max_name_w + spacing(16) + metric + lề hai bên (24)
            w = max(180, 8 + 6 + max_name_w + 16 + metric_w + 24)
            if count <= 1:
                h = 44
            else:
                h = max(44, count * 42 + 8)
            self.setMinimumSize(w, h)
            self.resize(w, h)

    def show_minimal_style_menu(self):
        menu = QMenu(self)
        menu.setStyleSheet(self.get_menu_stylesheet())
        title_act = menu.addAction("🎨 Chọn Kiểu Hiển Thị")
        title_act.setEnabled(False)
        menu.addSeparator()

        a1 = menu.addAction("Kiểu 1: Vòng tròn đôi (Twin Rings - Mặc định)", lambda: self.set_minimal_style("twin_rings"))
        a1.setCheckable(True)
        a1.setChecked(self.minimal_style == "twin_rings")

        a2 = menu.addAction("Kiểu 2: Vòng kép đồng tâm (Concentric Rings)", lambda: self.set_minimal_style("concentric_rings"))
        a2.setCheckable(True)
        a2.setChecked(self.minimal_style == "concentric_rings")

        a3 = menu.addAction("Kiểu 3: Thanh tiến trình mini (Micro Bars)", lambda: self.set_minimal_style("micro_bars"))
        a3.setCheckable(True)
        a3.setChecked(self.minimal_style == "micro_bars")

        a4 = menu.addAction("Kiểu 4: Thẻ số điện tử HUD (Digital Pill)", lambda: self.set_minimal_style("digital_pill"))
        a4.setCheckable(True)
        a4.setChecked(self.minimal_style == "digital_pill")

        menu.exec(QCursor.pos())

    def show_minimal_layout_menu(self):
        menu = QMenu(self)
        menu.setStyleSheet(self.get_menu_stylesheet())
        title_act = menu.addAction("📐 Chọn Bố Cục Khung")
        title_act.setEnabled(False)
        menu.addSeparator()

        l1 = menu.addAction("Khung Dọc (Vertical Dock - Mặc định)", lambda: self.set_minimal_layout("vertical"))
        l1.setCheckable(True)
        l1.setChecked(self.minimal_layout == "vertical")

        l2 = menu.addAction("Thanh Ngang (Horizontal Bar)", lambda: self.set_minimal_layout("horizontal"))
        l2.setCheckable(True)
        l2.setChecked(self.minimal_layout == "horizontal")

        menu.exec(QCursor.pos())

    def _get_edge_at(self, pos):
        if not self.is_floating:
            return None
        margin = 8
        x = pos.x()
        y = pos.y()
        w = self.width()
        h = self.height()

        left = x <= margin
        right = x >= w - margin
        top = y <= margin
        bottom = y >= h - margin

        if top and left: return "TOP_LEFT"
        if top and right: return "TOP_RIGHT"
        if bottom and left: return "BOTTOM_LEFT"
        if bottom and right: return "BOTTOM_RIGHT"
        if left: return "LEFT"
        if right: return "RIGHT"
        if top: return "TOP"
        if bottom: return "BOTTOM"
        return None

    def _update_cursor_for_edge(self, edge):
        if edge in ("TOP_LEFT", "BOTTOM_RIGHT"):
            self.setCursor(Qt.SizeFDiagCursor)
        elif edge in ("TOP_RIGHT", "BOTTOM_LEFT"):
            self.setCursor(Qt.SizeBDiagCursor)
        elif edge in ("LEFT", "RIGHT"):
            self.setCursor(Qt.SizeHorCursor)
        elif edge in ("TOP", "BOTTOM"):
            self.setCursor(Qt.SizeVerCursor)
        else:
            self.setCursor(Qt.ArrowCursor)

    def enterEvent(self, event):
        super().enterEvent(event)
        # Khi rê chuột vào cửa sổ nổi hoặc siêu thu nhỏ: Tự động sáng rõ 100%
        if self.is_minimal:
            self.setWindowOpacity(1.0)
        elif self.is_floating:
            self.setWindowOpacity(1.0)

    def leaveEvent(self, event):
        super().leaveEvent(event)
        # Khi chuột rời khỏi cửa sổ: Tự động mờ trong suốt
        if self.is_minimal:
            self.setWindowOpacity(0.94)
            self.setCursor(Qt.ArrowCursor)
        elif self.is_floating:
            self.setWindowOpacity(0.80)
            self.setCursor(Qt.ArrowCursor)

    def mouseDoubleClickEvent(self, event):
        if self.is_minimal and event.button() == Qt.LeftButton:
            # Không tự động phóng to khi ở dạng bong bóng
            event.accept()
        else:
            super().mouseDoubleClickEvent(event)

    def keyPressEvent(self, event):
        if self.is_minimal and event.key() == Qt.Key_Escape:
            self.close()
            event.accept()
            return
        super().keyPressEvent(event)

    def mousePressEvent(self, event):
        super().mousePressEvent(event)
        if (self.is_floating or self.is_minimal) and event.button() == Qt.LeftButton:
            edge = self._get_edge_at(event.pos()) if self.is_floating else None
            if edge:
                self._resizing = True
                self._resize_edge = edge
                self._press_pos = event.globalPosition().toPoint()
                self._press_geo = self.geometry()
                event.accept()
            else:
                self._is_dragging = True
                self._drag_pos = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
                event.accept()

    def mouseMoveEvent(self, event):
        super().mouseMoveEvent(event)
        if self.is_floating or self.is_minimal:
            if self._resizing and self._press_geo and self._press_pos and self.is_floating:
                diff = event.globalPosition().toPoint() - self._press_pos
                geo = QRect(self._press_geo)
                edge = self._resize_edge
                min_w = self.minimumWidth()
                min_h = self.minimumHeight()

                if "RIGHT" in edge:
                    geo.setWidth(max(min_w, self._press_geo.width() + diff.x()))
                if "BOTTOM" in edge:
                    geo.setHeight(max(min_h, self._press_geo.height() + diff.y()))
                if "LEFT" in edge:
                    new_w = max(min_w, self._press_geo.width() - diff.x())
                    geo.setLeft(self._press_geo.right() - new_w)
                if "TOP" in edge:
                    new_h = max(min_h, self._press_geo.height() - diff.y())
                    geo.setTop(self._press_geo.bottom() - new_h)

                self.setGeometry(geo)
                self.user_manually_resized = True
                event.accept()
            elif self._is_dragging and hasattr(self, '_drag_pos') and self._drag_pos:
                self.move(event.globalPosition().toPoint() - self._drag_pos)
                event.accept()
            elif not event.buttons() and self.is_floating:
                edge = self._get_edge_at(event.pos())
                self._update_cursor_for_edge(edge)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        if self.is_floating or self.is_minimal:
            self._resizing = False
            self._is_dragging = False
            if self.is_floating:
                edge = self._get_edge_at(event.pos())
                self._update_cursor_for_edge(edge)

    def get_menu_stylesheet(self):
        t = self.current_theme
        return f"""
            QMenu {{
                background-color: {t['card_bg']};
                color: {t['text_primary']};
                border: 1px solid {t['card_border']};
                border-radius: 8px;
                padding: 6px;
                font-size: 12px;
                font-family: {FONT_FAMILY};
            }}
            QMenu::item {{
                padding: 6px 20px;
                border-radius: 5px;
                background-color: transparent;
                color: {t['text_primary']};
            }}
            QMenu::item:selected {{
                background-color: {t['btn_pri_bg']};
                color: #ffffff;
            }}
            QMenu::item:disabled {{
                color: {t['text_muted']};
                background-color: transparent;
            }}
            QMenu::separator {{
                height: 1px;
                background-color: {t['card_border']};
                margin: 4px 8px;
            }}
        """

    def apply_theme(self):
        t = self.current_theme
        is_dark = self.theme_name == "dark"

        menu_css = self.get_menu_stylesheet()
        app_inst = QApplication.instance()
        if app_inst:
            app_inst.setStyleSheet(menu_css)
        if hasattr(self, "options_menu"):
            self.options_menu.setStyleSheet(menu_css)
        if hasattr(self, "menu_min_style"):
            self.menu_min_style.setStyleSheet(menu_css)
        if hasattr(self, "menu_min_layout"):
            self.menu_min_layout.setStyleSheet(menu_css)
        if hasattr(self, "tray_icon") and self.tray_icon.contextMenu():
            self.tray_icon.contextMenu().setStyleSheet(menu_css)
        
        # Cập nhật icon Heroicons
        self.btn_add.setIcon(heroicon(HEROICONS["plus"], t["btn_pri_text"], size=16))
        self.btn_menu.setIcon(heroicon(HEROICONS["bars_3"], t["toolbar_btn_text"], size=18))
        
        self.floating_act.setIcon(heroicon(HEROICONS["floating"], t["text_primary"], size=16))
        self.minimal_act.setIcon(heroicon(HEROICONS["fit"], t["text_primary"], size=16))
        self.menu_min_style.setIcon(heroicon(HEROICONS["swatch"], t["text_primary"], size=16))
        self.menu_min_layout.setIcon(heroicon(HEROICONS["squares"], t["text_primary"], size=16))
        self.hide_offline_act.setIcon(heroicon(HEROICONS["eye"], t["text_primary"], size=16))
        self.fit_act.setIcon(heroicon(HEROICONS["fit"], t["text_primary"], size=16))
        self.ontop_act.setIcon(heroicon(HEROICONS["pin"], t["text_primary"], size=16))
        
        self.theme_act.setIcon(heroicon(HEROICONS["sun" if is_dark else "moon"], t["text_primary"], size=16))
        self.theme_act.setText("Chế độ sáng" if is_dark else "Chế độ tối")
        
        self.ip_act.setIcon(heroicon(HEROICONS["globe"], t["text_primary"], size=16))

        # Icon cho mini header (Cửa sổ nổi)
        self.btn_exit_float.setIcon(heroicon(HEROICONS["fit"], t["toolbar_btn_text"], size=14))
        self.btn_close_app.setIcon(heroicon(HEROICONS["close"], t["toolbar_btn_text"], size=14))

        # Dynamic Island style (iPhone Pill - Tự thích ứng Dark / Light Mode)
        if is_dark:
            wrapper_bg = "#000000"
            wrapper_border = "1px solid rgba(255, 255, 255, 0.16)"
            empty_text_color = "#94a3b8"
        else:
            wrapper_bg = "rgba(255, 255, 255, 0.96)"
            wrapper_border = "1px solid rgba(0, 0, 0, 0.14)"
            empty_text_color = "#64748b"

        self.minimal_wrapper.setStyleSheet(f"""
            QWidget#minimalWrapper {{
                background-color: {wrapper_bg};
                border: {wrapper_border};
                border-radius: 20px;
            }}
            QWidget#minimalWrapper QScrollArea,
            QWidget#minimalWrapper QScrollArea > QWidget,
            QWidget#minimalWrapper QScrollArea > QWidget > QWidget,
            QWidget#minimalScroll,
            QWidget#minimalContainer,
            MinimalHostItem {{
                background: transparent !important;
                background-color: transparent !important;
                border: none !important;
            }}
            MinimalHostItem:hover {{
                background: transparent !important;
                background-color: transparent !important;
                border: none !important;
            }}
        """)
        self.min_empty_lbl.setStyleSheet(f"font-size: 11px; padding: 8px; font-family: {FONT_FAMILY}; color: {empty_text_color};")

        self.mini_header.setStyleSheet(f"""
            QWidget {{
                background-color: {t['floating_header_bg']};
                border-bottom: 1px solid {t['toolbar_border']};
            }}
            QToolButton {{
                background: transparent;
                border: none;
                border-radius: 4px;
                padding: 3px;
            }}
            QToolButton:hover {{
                background-color: {t['btn_sec_hover']};
            }}
        """)
        self.mini_title.setStyleSheet(f"color: {t['text_secondary']}; font-size: 11px; font-weight: 600; font-family: {FONT_FAMILY};")

        # Style toàn bộ MainWindow
        main_bg_css = "background-color: transparent;" if self.is_minimal else f"background-color: {t['app_bg']};"
        self.setStyleSheet(f"""
            QMainWindow {{
                {main_bg_css}
                font-family: {FONT_FAMILY};
            }}
            QWidget#centralWidget, QScrollArea#mainScroll, QScrollArea#mainScroll > QWidget, QScrollArea#mainScroll > QWidget > QWidget {{
                background-color: {t['app_bg']};
                border: none;
            }}
            QToolBar {{
                background-color: {t['toolbar_bg']};
                border-bottom: 1px solid {t['toolbar_border']};
                spacing: 6px;
                padding: 4px 8px;
            }}
            QToolButton {{
                background: {t['btn_sec_bg']};
                color: {t['btn_sec_text']};
                border: 1px solid {t['btn_sec_border']};
                border-radius: 6px;
                padding: 5px 10px;
                font-size: 12px;
                font-weight: 600;
                font-family: {FONT_FAMILY};
            }}
            QToolButton:hover {{
                background-color: {t['btn_sec_hover']};
            }}
            QStatusBar {{
                background-color: {t['toolbar_bg']};
                border-top: 1px solid {t['toolbar_border']};
                color: {t['text_secondary']};
                font-size: 11px;
                font-family: {FONT_FAMILY};
            }}
            QScrollBar:vertical {{
                background: transparent;
                width: 6px;
                margin: 0;
            }}
            QScrollBar::handle:vertical {{
                background: {t['bar_bg']};
                border-radius: 3px;
                min-height: 20px;
            }}
            QScrollBar::handle:vertical:hover {{
                background: {t['text_muted']};
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height: 0;
            }}
            QMenu {{
                background-color: {t['card_bg']};
                color: {t['text_primary']};
                border: 1px solid {t['card_border']};
                border-radius: 8px;
                padding: 6px;
                font-size: 12px;
                font-family: {FONT_FAMILY};
            }}
            QMenu::item {{
                padding: 7px 22px;
                border-radius: 5px;
            }}
            QMenu::item:selected {{
                background-color: {t['btn_pri_bg']};
                color: #ffffff;
            }}
            QMenu::separator {{
                height: 1px;
                background-color: {t['card_border']};
                margin: 4px 8px;
            }}
            QDialog {{
                background-color: {t['dialog_bg']};
                color: {t['text_primary']};
                font-family: {FONT_FAMILY};
            }}
            QLineEdit {{
                background-color: {t['input_bg']};
                color: {t['text_primary']};
                border: 1px solid {t['input_border']};
                border-radius: 6px;
                padding: 6px 10px;
                font-size: 12px;
                font-family: {FONT_FAMILY};
            }}
            QLabel {{
                font-family: {FONT_FAMILY};
            }}
        """)

        # Style nút "Thêm máy" màu xanh nổi bật
        self.btn_add.setStyleSheet(f"""
            QToolButton {{
                background-color: {t['btn_pri_bg']};
                color: {t['btn_pri_text']};
                border: none;
                border-radius: 6px;
                padding: 5px 12px;
                font-size: 12px;
                font-weight: 600;
                font-family: {FONT_FAMILY};
            }}
            QToolButton:hover {{
                background-color: {t['btn_pri_hover']};
            }}
        """)

        self.brand_lbl.setStyleSheet(f"color: {t['text_primary']}; font-weight: 600; font-size: 14px; font-family: {FONT_FAMILY};")
        self.empty_lbl.setStyleSheet(f"color: {t['text_muted']}; font-size: 13px; padding: 40px 15px; font-family: {FONT_FAMILY};")
        self.status_lbl.setStyleSheet(f"color: {t['text_secondary']}; padding-right: 12px; font-weight: 600; font-size: 11px; font-family: {FONT_FAMILY};")

        for card in self.cards.values():
            card.apply_theme(t)
        for item in self.minimal_items.values():
            item.apply_theme(t)

    def toggle_theme(self):
        new_theme = "light" if self.theme_name == "dark" else "dark"
        self.theme_name = new_theme
        self.current_theme = THEMES[new_theme]
        self.cfg["theme"] = new_theme
        save_config(self.cfg)
        self.apply_theme()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'sizegrip') and self.sizegrip:
            self.sizegrip.move(self.width() - 16, self.height() - 16)
            self.sizegrip.raise_()
        if event.spontaneous():
            self.user_manually_resized = True

    def on_fit_clicked(self):
        self.user_manually_resized = False
        self.fit_to_content(force=True)

    def fit_to_content(self, force=False):
        if self.is_minimal:
            self.fit_minimal_size()
            return

        if self.user_manually_resized and not force:
            return
        
        screen = QGuiApplication.primaryScreen().availableGeometry()
        max_h = int(screen.height() * 0.85)

        visible_cards = [c for c in self.cards.values() if not c.isHidden()]
        count = len(visible_cards)

        if self.is_floating:
            min_h = 160
            if count == 0:
                target_h = min_h
            else:
                needed_h = count * 135 + 50
                target_h = max(min_h, min(needed_h, max_h))
            target_w = self.width() if self.user_manually_resized else min(350, screen.width() - 40)
        else:
            min_h = 230
            if count == 0:
                target_h = min_h
            else:
                needed_h = count * 195 + 110
                target_h = max(min_h, min(needed_h, max_h))
            target_w = self.width() if self.user_manually_resized else min(400, screen.width() - 40)

        self.resize(target_w, target_h)

    def toggle_hide_offline(self):
        self.user_manually_resized = False
        self.cfg["hide_offline"] = self.hide_offline_act.isChecked()
        save_config(self.cfg)
        self.update_cards_visibility()

    def update_cards_visibility(self):
        is_hide = self.hide_offline_act.isChecked()
        visible_count = 0
        online_count = 0
        total_count = len(self.cards)

        for card in self.cards.values():
            if card.is_online is True:
                online_count += 1
            
            if is_hide and card.is_online is False:
                card.hide()
            else:
                card.show()
                visible_count += 1

        min_visible = 0
        for item in self.minimal_items.values():
            if is_hide and item.is_online is False:
                item.hide()
            else:
                item.show()
                min_visible += 1

        if is_hide and total_count > 0 and visible_count == 0:
            self.empty_lbl.show()
        else:
            self.empty_lbl.hide()

        if is_hide and total_count > 0 and min_visible == 0:
            self.min_empty_lbl.show()
        else:
            self.min_empty_lbl.hide()

        self.status_lbl.setText(f"Online: {online_count}/{total_count}")

        # Cập nhật tooltip và thống kê khay hệ thống
        if hasattr(self, "tray_icon") and self.tray_icon:
            offline_count = total_count - online_count
            self.act_tray_stats.setText(f"🟢 {online_count} Online | 🔴 {offline_count} Offline")
            self.tray_icon.setToolTip(f"{APP_TITLE}\n🟢 {online_count}/{total_count} máy Online ({offline_count} Offline)")

        if self.is_minimal:
            self.fit_minimal_size()
        elif self.last_visible_count != visible_count:
            self.last_visible_count = visible_count
            self.fit_to_content(force=False)

    def toggle_ontop(self):
        flags = self.windowFlags()
        if self.ontop_act.isChecked():
            self.setWindowFlags(flags | Qt.WindowStaysOnTopHint)
        else:
            if not self.is_floating:
                self.setWindowFlags(Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint)
        self.show()

    def delete_host(self, idx):
        if QMessageBox.question(self, "Xác nhận", f"Bạn có chắc chắn muốn xóa máy '{self.cfg['hosts'][idx]['name']}' không?") == QMessageBox.Yes:
            del self.cfg["hosts"][idx]
            save_config(self.cfg)
            for c in self.cards.values(): c.setParent(None); c.deleteLater()
            self.cards = {}
            for m in self.minimal_items.values(): m.setParent(None); m.deleteLater()
            self.minimal_items = {}
            self.refresh()
            self.update_cards_visibility()

    def show_tailscale_info(self):
        try: ip = subprocess.check_output(["tailscale", "ip", "-4"], text=True).strip().split('\n')[0]
        except: ip = "Không tìm thấy"
        QMessageBox.information(self, "Tailscale Info", f"IP của bạn: {ip}")

    def send_control(self, host, action, app_path=None, url=None):
        w = ControlWorker(host, self.cfg.get("token", ""), action, app_path, url)
        w.signals.finished.connect(lambda msg: QMessageBox.information(self, "Điều khiển từ xa", msg))
        self.threadpool.start(w)

    def open_app_link_manager(self, tab=0):
        dlg = AppAndLinkManagerDialog(self, initial_tab=tab)
        dlg.exec()

    def open_config_file(self):
        cfg_path = get_config_path()
        if not cfg_path.exists():
            save_config(self.cfg)
        try:
            if sys.platform == "win32":
                os.startfile(str(cfg_path))
            else:
                subprocess.Popen(["xdg-open", str(cfg_path)])
        except Exception as e:
            QMessageBox.warning(self, "Không thể mở file", f"Đường dẫn: {cfg_path}\nLỗi: {e}")

    def import_config_file(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, "Chọn file cấu hình dashboard_config.json", "",
            "JSON Files (*.json);;All Files (*.*)"
        )
        if not file_path:
            return
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data, dict):
                raise ValueError("Nội dung file không đúng định dạng JSON.")
            
            self.cfg.update(data)
            save_config(self.cfg)
            
            # Xóa các card cũ và nạp lại
            for c in list(self.cards.values()):
                c.setParent(None)
                c.deleteLater()
            self.cards = {}
            for m in list(self.minimal_items.values()):
                m.setParent(None)
                m.deleteLater()
            self.minimal_items = {}
            self.refresh()
            self.update_cards_visibility()
            
            host_count = len(self.cfg.get("hosts", []))
            QMessageBox.information(
                self, "Nhập cấu hình thành công",
                f"Đã nạp thành công cấu hình từ:\n{file_path}\n\nĐã thêm {host_count} máy tính vào Dashboard!"
            )
        except Exception as e:
            QMessageBox.critical(self, "Lỗi đọc file", f"Không thể đọc file cấu hình:\n{e}")

    def add_host(self):
        dlg = HostDialog(self)
        if dlg.exec():
            self.cfg["hosts"].append(dlg.get_data())
            save_config(self.cfg)
            self.refresh()

    def refresh(self):
        for idx, host in enumerate(self.cfg.get("hosts", [])):
            if idx not in self.cards:
                c = HostCard(idx, host, self)
                c.set_floating_mode(self.is_floating)
                self.cards[idx] = c
                self.layout.insertWidget(self.layout.count() - 1, c)
            if idx not in self.minimal_items:
                m = MinimalHostItem(idx, host, self)
                self.minimal_items[idx] = m
                self.minimal_items_layout.addWidget(m)
            w = FetchWorker(idx, host, self.cfg.get("token", ""), self.fetch_signals)
            self.threadpool.start(w)
        self.update_cards_visibility()

    @Slot(int, object, str)
    def on_finished(self, idx, data, error):
        if idx in self.cards:
            self.cards[idx].update_values(data, error)
        if idx in self.minimal_items:
            self.minimal_items[idx].update_values(data, error)
        self.update_cards_visibility()

    def _setup_system_tray(self):
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setIcon(get_dashboard_icon())
        self.tray_icon.setToolTip(f"{APP_TITLE} - Đang giám sát")

        tray_menu = QMenu(self)

        self.act_tray_open = tray_menu.addAction("🖥 Mở Bảng Điều Khiển", self.restore_from_tray)
        f = self.act_tray_open.font()
        f.setBold(True)
        self.act_tray_open.setFont(f)

        self.act_tray_floating = tray_menu.addAction("🪟 Chế độ Cửa Sổ Nổi (F11)", self.toggle_floating_mode)
        self.act_tray_floating.setCheckable(True)
        self.act_tray_floating.setChecked(self.is_floating)

        self.act_tray_minimal = tray_menu.addAction("📐 Chế độ Siêu Thu Nhỏ (F9)", self.toggle_minimal_mode)
        self.act_tray_minimal.setCheckable(True)
        self.act_tray_minimal.setChecked(self.is_minimal)

        tray_menu.addSeparator()

        self.act_tray_stats = tray_menu.addAction("🟢 0 Máy Online | 🔴 0 Offline")
        self.act_tray_stats.setEnabled(False)

        self.act_tray_refresh = tray_menu.addAction("🔄 Làm mới dữ liệu ngay", self.refresh)

        tray_menu.addSeparator()

        self.act_tray_autostart = tray_menu.addAction("🚀 Khởi động cùng Windows", self.toggle_autostart)
        self.act_tray_autostart.setCheckable(True)
        self.act_tray_autostart.setChecked(is_autostart_enabled())

        self.act_tray_notify = tray_menu.addAction("🔔 Báo động khi máy mất kết nối", self.toggle_notify_offline)
        self.act_tray_notify.setCheckable(True)
        self.act_tray_notify.setChecked(self.cfg.get("notify_offline", True))

        tray_menu.addSeparator()

        act_exit = tray_menu.addAction("❌ Thoát Dashboard", self.confirm_exit)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self.on_tray_activated)
        self.tray_icon.show()

    def on_tray_activated(self, reason):
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self.restore_from_tray()

    def restore_from_tray(self):
        if self.is_minimal:
            self.toggle_minimal_mode()
        if self.isHidden():
            self.show()
        if self.isMinimized():
            self.showNormal()
        self.raise_()
        self.activateWindow()

    def toggle_autostart(self):
        cur = is_autostart_enabled()
        new_val = not cur
        ok, msg = set_autostart(new_val)
        if ok:
            if hasattr(self, "autostart_act"):
                self.autostart_act.setChecked(new_val)
            if hasattr(self, "act_tray_autostart"):
                self.act_tray_autostart.setChecked(new_val)
        else:
            QMessageBox.warning(self, "Lỗi Autostart", f"Không thể thay đổi thiết lập khởi động cùng Windows:\n{msg}")

    def toggle_notify_offline(self):
        cur = self.cfg.get("notify_offline", True)
        new_val = not cur
        self.cfg["notify_offline"] = new_val
        save_config(self.cfg)
        if hasattr(self, "notify_act"):
            self.notify_act.setChecked(new_val)
        if hasattr(self, "act_tray_notify"):
            self.act_tray_notify.setChecked(new_val)

    def closeEvent(self, event):
        if hasattr(self, "tray_icon") and self.tray_icon and self.tray_icon.isVisible():
            event.ignore()
            self.hide()
            if not self.has_notified_tray:
                self.tray_icon.showMessage(
                    "LAN Monitor Dashboard",
                    "Dashboard vẫn đang chạy ngầm trong khay hệ thống để giám sát các máy.",
                    QSystemTrayIcon.Information,
                    2500
                )
                self.has_notified_tray = True
        else:
            event.accept()

    def confirm_exit(self):
        reply = QMessageBox.question(
            self,
            "Xác nhận thoát",
            "Bạn có chắc chắn muốn tắt hoàn toàn LAN Monitor Dashboard không?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        if reply == QMessageBox.Yes:
            if hasattr(self, "tray_icon") and self.tray_icon:
                self.tray_icon.hide()
            QApplication.quit()

if __name__ == "__main__":
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("LANMonitor.Dashboard.1.0")
        except Exception:
            pass

    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setApplicationName("LANMonitorDashboard")
    app.setQuitOnLastWindowClosed(False)
    app.setWindowIcon(get_dashboard_icon())
    
    # Thiết lập font chuẩn Segoe UI cho Windows (hỗ trợ ClearType và tiếng Việt chuẩn 100%)
    app_font = QFont("Segoe UI", 10)
    app_font.setStyleStrategy(QFont.PreferAntialias)
    app.setFont(app_font)
    
    win = MainWindow()
    
    start_in_tray = "--tray" in sys.argv or "--minimized" in sys.argv
    start_floating = "--floating" in sys.argv
    start_minimal = "--minimal" in sys.argv

    if start_minimal:
        win.show()
        win.toggle_minimal_mode()
    elif start_floating:
        win.show()
        win.toggle_floating_mode()
    elif not start_in_tray:
        win.show()

    sys.exit(app.exec())
