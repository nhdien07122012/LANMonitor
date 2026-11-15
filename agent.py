import sys
import os
import time
import json
import socket
import platform
import subprocess
import threading
import secrets
from datetime import datetime
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import psutil

# Windows registry for autostart
if platform.system() == "Windows":
    import winreg

from PySide6.QtCore import Qt, QTimer, QObject, Signal, QByteArray, QSize
from PySide6.QtGui import QIcon, QPixmap, QPainter, QColor, QPen, QFont, QCursor
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QLabel, QPushButton, QLineEdit, QSpinBox, QCheckBox,
    QProgressBar, QTabWidget, QTableWidget, QTableWidgetItem, QHeaderView,
    QSystemTrayIcon, QMenu, QMessageBox, QFrame, QScrollArea, QSizePolicy
)
from PySide6.QtSvg import QSvgRenderer

VERSION = "1.1.0"
DEFAULT_PORT = 8765
DEFAULT_TOKEN = "LANMONITOR-CHANGE-ME"
RUN_REG_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
APP_NAME = "LANMonitorAgent"

# ---------- Config Helpers ----------
def get_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

def get_config_path() -> Path:
    return get_base_dir() / "agent_config.json"

def load_config() -> dict:
    cfg = {
        "port": DEFAULT_PORT,
        "token": DEFAULT_TOKEN,
        "name": socket.gethostname(),
        "interval": 1.0,
        "autostart": False
    }
    path = get_config_path()
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            cfg.update(data)
        except Exception:
            pass
    return cfg

def save_config(cfg: dict) -> bool:
    try:
        path = get_config_path()
        path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")
        return True
    except Exception:
        return False

# Global runtime configuration
CFG = load_config()
PORT = int(CFG.get("port", DEFAULT_PORT))
TOKEN = str(CFG.get("token", DEFAULT_TOKEN))

# ---------- Network & Metrics Helpers ----------
_prev_net = None
_prev_time = None
_prev_lock = threading.Lock()

def bytes_per_sec():
    global _prev_net, _prev_time
    now = time.time()
    try:
        cur = psutil.net_io_counters()
    except Exception:
        return 0.0, 0.0
    with _prev_lock:
        if _prev_net is None:
            _prev_net, _prev_time = cur, now
            return 0.0, 0.0
        dt = max(now - _prev_time, 0.001)
        down = (cur.bytes_recv - _prev_net.bytes_recv) / dt
        up = (cur.bytes_sent - _prev_net.bytes_sent) / dt
        _prev_net, _prev_time = cur, now
    return max(down, 0.0), max(up, 0.0)

def gpu_info():
    result = []
    try:
        p = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2
        )
        if platform.system() == "Windows" and p.returncode == 0:
            for line in p.stdout.strip().splitlines():
                parts = [x.strip() for x in line.split(",")]
                if len(parts) >= 5:
                    result.append({
                        "name": parts[0],
                        "util": float(parts[1]) if parts[1].replace(".", "", 1).isdigit() else None,
                        "mem_used_mb": float(parts[2]) if parts[2].replace(".", "", 1).isdigit() else None,
                        "mem_total_mb": float(parts[3]) if parts[3].replace(".", "", 1).isdigit() else None,
                        "temp_c": float(parts[4]) if parts[4].replace(".", "", 1).isdigit() else None,
                    })
    except Exception:
        pass
    return result

def temp_info():
    out = {}
    try:
        sensors = psutil.sensors_temperatures()
        for group, entries in sensors.items():
            vals = []
            for e in entries:
                if e.current is not None:
                    vals.append(float(e.current))
            if vals:
                out[group] = round(max(vals), 1)
    except Exception:
        pass
    return out

def get_lan_ip():
    """Return the IPv4 address used for the LAN route, avoiding 127.0.0.1."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("192.0.0.1", 1))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "127.0.0.1"

def get_tailscale_ip():
    """Detect Tailscale IPv4 address if available."""
    try:
        addrs = psutil.net_if_addrs()
        # 1. Search for interface with 'tailscale' in name
        for iface_name, iface_addrs in addrs.items():
            if "tailscale" in iface_name.lower():
                for addr in iface_addrs:
                    if addr.family == socket.AF_INET:
                        return addr.address
        # 2. Search for IP in CGNAT / Tailscale range: 100.64.0.0/10
        for iface_name, iface_addrs in addrs.items():
            for addr in iface_addrs:
                if addr.family == socket.AF_INET:
                    parts = addr.address.split(".")
                    if len(parts) == 4 and parts[0] == "100":
                        second = int(parts[1])
                        if 64 <= second <= 127:
                            return addr.address
    except Exception:
        pass
    return None

def snapshot():
    down, up = bytes_per_sec()
    vm = psutil.virtual_memory()
    root_path = "C:\\" if platform.system() == "Windows" else "/"
    try:
        disk = psutil.disk_usage(root_path)
    except Exception:
        class DiskMock:
            percent = 0
            free = 0
        disk = DiskMock()
    boot = psutil.boot_time()
    gpus = gpu_info()
    return {
        "version": VERSION,
        "hostname": CFG.get("name") or socket.gethostname(),
        "ip": get_lan_ip(),
        "tailscale_ip": get_tailscale_ip(),
        "timestamp": time.time(),
        "cpu_percent": round(psutil.cpu_percent(interval=0.15), 1),
        "cpu_count": psutil.cpu_count(logical=True),
        "ram_percent": vm.percent,
        "ram_used_gb": round(vm.used / 1024**3, 2),
        "ram_total_gb": round(vm.total / 1024**3, 2),
        "disk_percent": disk.percent,
        "disk_free_gb": round(disk.free / 1024**3, 2),
        "download_bps": round(down, 1),
        "upload_bps": round(up, 1),
        "gpu": gpus,
        "temperatures": temp_info(),
        "uptime_sec": max(0, int(time.time() - boot)),
    }

# ---------- Windows Autostart & Firewall ----------
def is_autostart_enabled() -> bool:
    if platform.system() != "Windows":
        return False
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_REG_KEY, 0, winreg.KEY_READ) as key:
            winreg.QueryValueEx(key, APP_NAME)
            return True
    except Exception:
        return False

def set_autostart(enable: bool) -> tuple[bool, str]:
    if platform.system() != "Windows":
        return False, "Tính năng chỉ hỗ trợ trên hệ điều hành Windows"
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_REG_KEY, 0, winreg.KEY_SET_VALUE) as key:
            if enable:
                if getattr(sys, "frozen", False):
                    exe_path = f'"{sys.executable}" --tray'
                else:
                    exe_path = f'"{sys.executable}" "{Path(__file__).resolve()}" --tray'
                winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, exe_path)
            else:
                try:
                    winreg.DeleteValue(key, APP_NAME)
                except FileNotFoundError:
                    pass
        return True, "Thành công"
    except Exception as e:
        return False, str(e)

def open_firewall_rule(port: int) -> tuple[bool, str]:
    if platform.system() != "Windows":
        return False, "Chỉ hỗ trợ Windows Firewall"
    rule_name = f"LAN Monitor Agent {port}"
    cmd = f'netsh advfirewall firewall add rule name="{rule_name}" dir=in action=allow protocol=TCP localport={port} profile=any'
    ps_cmd = f'Start-Process cmd -ArgumentList \'/c {cmd}\' -Verb RunAs'
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd], check=True)
        return True, f"Đã gửi yêu cầu cấp quyền mở cổng {port} trên Windows Firewall!"
    except Exception as e:
        return False, f"Không thể thêm quy tắc Firewall: {e}"

# ---------- SVG Heroicons Helper ----------
HEROICONS = {
    "server": "M5.25 14.25h13.5m-13.5 3h13.5m-13.5 3h13.5M6 6.75h12M6 9.75h12M4.5 3.75h15a1.5 1.5 0 0 1 1.5 1.5v13.5a1.5 1.5 0 0 1-1.5 1.5h-15a1.5 1.5 0 0 1-1.5-1.5V5.25a1.5 1.5 0 0 1 1.5-1.5Z",
    "play": "M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 0 1 0 1.971l-11.54 6.347a1.125 1.125 0 0 1-1.667-.985V5.653Z",
    "pause": "M15.75 5.25v13.5m-7.5-13.5v13.5",
    "refresh": "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99",
    "copy": "M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9a.75.75 0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 0 1 1.927-.184",
    "shield": "M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z",
    "rocket": "M15.59 14.37a6 6 0 0 1-5.84 7.38v-4.8m5.84-2.58a14.98 14.98 0 0 0 6.16-12.12A14.98 14.98 0 0 0 9.631 8.41m5.96 5.96a14.926 14.926 0 0 1-5.841 2.58m-.119-8.54a6 6 0 0 0-7.381 5.84h4.8m2.581-5.84a14.927 14.927 0 0 0-2.58 5.84m2.699 2.7 4.243 4.243",
    "key": "M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1 1 21.75 8.25Z",
    "eye": "M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
    "trash": "M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0",
    "power": "M5.636 5.636a9 9 0 1 0 12.728 0M12 3v9",
    "check": "m4.5 12.75 6 6 9-13.5",
    "close": "M6 18L18 6M6 6l12 12",
    "chevron_down": "m19.5 8.25-7.5 7.5-7.5-7.5"
}

def heroicon(path_d: str, color: str = "#94a3b8", size: int = 18, stroke_width: str = "2") -> QIcon:
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="{stroke_width}" stroke="{color}"><path stroke-linecap="round" stroke-linejoin="round" d="{path_d}" /></svg>'
    renderer = QSvgRenderer(QByteArray(svg.encode("utf-8")))
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    renderer.render(painter)
    painter.end()
    return QIcon(pixmap)

def get_app_icon() -> QIcon:
    candidates = []
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        candidates.append(Path(sys._MEIPASS) / "app-agent.ico")
    candidates.append(get_base_dir() / "app-agent.ico")
    candidates.append(Path("app-agent.ico"))

    for p in candidates:
        if p.exists():
            return QIcon(str(p))

    # Fallback programmatic icon
    pix = QPixmap(64, 64)
    pix.fill(Qt.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor("#0f172a"))
    painter.setPen(QPen(QColor("#0ea5e9"), 3))
    painter.drawRoundedRect(4, 4, 56, 56, 12, 12)
    # Server rack units
    painter.setBrush(QColor("#1e293b"))
    painter.setPen(QPen(QColor("#38bdf8"), 1.5))
    painter.drawRoundedRect(12, 16, 40, 10, 3, 3)
    painter.drawRoundedRect(12, 29, 40, 10, 3, 3)
    painter.drawRoundedRect(12, 42, 40, 10, 3, 3)
    # Green LED
    painter.setBrush(QColor("#10b981"))
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(42, 19, 4, 4)
    painter.drawEllipse(42, 32, 4, 4)
    painter.drawEllipse(42, 45, 4, 4)
    painter.end()
    return QIcon(pix)

# ---------- Qt Signals & Server Manager ----------
class AgentSignals(QObject):
    request_logged = Signal(dict)
    server_state_changed = Signal(bool, str)

_GLOBAL_SIGNALS = None

def get_signals() -> AgentSignals:
    global _GLOBAL_SIGNALS
    if _GLOBAL_SIGNALS is None:
        _GLOBAL_SIGNALS = AgentSignals()
    return _GLOBAL_SIGNALS

class AgentHTTPHandler(BaseHTTPRequestHandler):
    server_version = f"LANMonitorAgent/{VERSION}"

    def log_message(self, fmt, *args):
        # Mute default stderr logging
        return

    def send_json(self, code, data, log_detail=""):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            pass

        # Log request to GUI
        client_ip = self.client_address[0] if self.client_address else "Unknown"
        get_signals().request_logged.emit({
            "time": datetime.now().strftime("%H:%M:%S"),
            "client": client_ip,
            "method": self.command,
            "path": self.path,
            "status": code,
            "detail": log_detail or ("OK" if code == 200 else f"HTTP {code}")
        })

    def do_POST(self):
        token = self.headers.get("X-LAN-Monitor-Token", "")
        if TOKEN and token != TOKEN:
            self.send_json(401, {"ok": False, "error": "Unauthorized"}, "Sai mã Secret Token")
            return

        parsed = urlparse(self.path)
        if parsed.path != "/control":
            self.send_json(404, {"ok": False, "error": "Not found"}, "Đường dẫn không tồn tại")
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode("utf-8"))
            action = data.get("action")
            
            if action == "shutdown":
                self.send_json(200, {"ok": True, "message": "Đang tắt máy..."}, "Lệnh: Tắt máy (Shutdown)")
                os.system("shutdown /s /t 0" if platform.system() == "Windows" else "sudo shutdown -h now")
            elif action == "reboot":
                self.send_json(200, {"ok": True, "message": "Đang khởi động lại..."}, "Lệnh: Khởi động lại (Reboot)")
                os.system("shutdown /r /t 0" if platform.system() == "Windows" else "sudo reboot")
            elif action == "sleep":
                self.send_json(200, {"ok": True, "message": "Đang chuyển chế độ ngủ..."}, "Lệnh: Chế độ ngủ (Sleep)")
                if platform.system() == "Windows":
                    os.system("rundll32.exe powrprof.dll,SetSuspendState 0,1,0")
            elif action == "run_app":
                app_path = data.get("app_path")
                if not app_path:
                    self.send_json(400, {"ok": False, "error": "No app_path provided"}, "Thiếu app_path")
                    return
                if app_path.startswith("http://") or app_path.startswith("https://"):
                    if platform.system() == "Windows":
                        os.startfile(app_path)
                    else:
                        import webbrowser
                        webbrowser.open(app_path)
                    self.send_json(200, {"ok": True, "message": f"Đã mở link: {app_path}"}, f"Mở link: {app_path}")
                else:
                    subprocess.Popen(app_path, shell=True)
                    self.send_json(200, {"ok": True, "message": f"Started {app_path}"}, f"Chạy ứng dụng: {app_path}")
            elif action == "open_url":
                url = data.get("url") or data.get("app_path")
                if not url:
                    self.send_json(400, {"ok": False, "error": "No url provided"}, "Thiếu URL")
                    return
                if not (url.startswith("http://") or url.startswith("https://")):
                    url = "https://" + url
                try:
                    if platform.system() == "Windows":
                        os.startfile(url)
                    else:
                        import webbrowser
                        webbrowser.open(url)
                    self.send_json(200, {"ok": True, "message": f"Đã mở link: {url}"}, f"Mở link: {url}")
                except Exception as e:
                    self.send_json(500, {"ok": False, "error": str(e)}, f"Lỗi mở link: {e}")
            else:
                self.send_json(400, {"ok": False, "error": "Invalid action"}, f"Lệnh không hợp lệ: {action}")
        except Exception as e:
            self.send_json(500, {"ok": False, "error": str(e)}, f"Lỗi xử lý POST: {e}")

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(200, {"ok": True, "version": VERSION, "hostname": CFG.get("name")}, "Kiểm tra kết nối (Health Check)")
            return

        if parsed.path != "/metrics":
            self.send_json(404, {"ok": False, "error": "Not found"}, "Đường dẫn không tồn tại")
            return

        token = self.headers.get("X-LAN-Monitor-Token", "")
        if TOKEN and token != TOKEN:
            self.send_json(401, {"ok": False, "error": "Unauthorized"}, "Sai mã Secret Token")
            return

        try:
            data = snapshot()
            self.send_json(200, data, "Thu thập thông số (Metrics)")
        except Exception as e:
            self.send_json(500, {"ok": False, "error": str(e)}, f"Lỗi thu thập thông số: {e}")

class AgentServerManager:
    def __init__(self):
        self.server = None
        self.thread = None
        self.is_running = False
        self.port = PORT
        self.total_requests = 0
        self.last_request_time = "-"

    def start(self, port: int = None) -> tuple[bool, str]:
        if port is not None:
            self.port = port
        if self.is_running:
            self.stop()
        try:
            self.server = ThreadingHTTPServer(("0.0.0.0", self.port), AgentHTTPHandler)
            self.server.daemon_threads = True
            self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
            self.thread.start()
            self.is_running = True
            get_signals().server_state_changed.emit(True, f"Đang lắng nghe 0.0.0.0:{self.port}")
            return True, f"Server đang chạy trên cổng {self.port}"
        except OSError as e:
            self.is_running = False
            err_msg = f"Cổng {self.port} đã bị chiếm dụng hoặc không thể mở: {e}"
            get_signals().server_state_changed.emit(False, err_msg)
            return False, err_msg
        except Exception as e:
            self.is_running = False
            get_signals().server_state_changed.emit(False, str(e))
            return False, str(e)

    def stop(self):
        if self.server:
            # Shutdown in separate daemon thread to avoid blocking GUI
            s = self.server
            threading.Thread(target=s.shutdown, daemon=True).start()
            try:
                s.server_close()
            except Exception:
                pass
            self.server = None
            self.thread = None
        self.is_running = False
        get_signals().server_state_changed.emit(False, "Đã tạm dừng dịch vụ")

# ---------- UI Stylesheet ----------
DARK_STYLE = """
QMainWindow, QWidget {
    background-color: #0f172a;
    color: #f8fafc;
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    font-size: 13px;
}

QTabWidget::pane {
    border: 1px solid #334155;
    background-color: #0f172a;
    border-radius: 8px;
    top: -1px;
}

QTabBar::tab {
    background-color: #1e293b;
    color: #94a3b8;
    padding: 8px 18px;
    margin-right: 4px;
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    font-weight: 600;
}

QTabBar::tab:selected {
    background-color: #0284c7;
    color: #ffffff;
}

QTabBar::tab:hover:!selected {
    background-color: #334155;
    color: #f8fafc;
}

QFrame.card {
    background-color: #1e293b;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 12px;
}

QLabel.title {
    font-size: 16px;
    font-weight: 700;
    color: #f8fafc;
}

QLabel.subtitle {
    font-size: 11px;
    color: #94a3b8;
}

QLabel.section-header {
    font-size: 13px;
    font-weight: 700;
    color: #38bdf8;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 4px;
}

QLabel.info-label {
    color: #94a3b8;
    font-size: 12px;
}

QLabel.info-value {
    color: #f8fafc;
    font-weight: 600;
    font-size: 13px;
}

QLineEdit, QSpinBox {
    background-color: #0f172a;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 6px 10px;
    color: #f8fafc;
    selection-background-color: #0284c7;
}

QLineEdit:focus, QSpinBox:focus {
    border: 1px solid #38bdf8;
}

QPushButton {
    background-color: #334155;
    color: #f8fafc;
    border: 1px solid #475569;
    border-radius: 6px;
    padding: 6px 14px;
    font-weight: 600;
}

QPushButton:hover {
    background-color: #475569;
}

QPushButton:pressed {
    background-color: #1e293b;
}

QPushButton.primary {
    background-color: #0284c7;
    border: 1px solid #0284c7;
    color: #ffffff;
}

QPushButton.primary:hover {
    background-color: #0369a1;
}

QPushButton.success {
    background-color: #10b981;
    border: 1px solid #10b981;
    color: #ffffff;
}

QPushButton.success:hover {
    background-color: #059669;
}

QPushButton.danger {
    background-color: #ef4444;
    border: 1px solid #ef4444;
    color: #ffffff;
}

QPushButton.danger:hover {
    background-color: #dc2626;
}

QPushButton.icon-btn {
    padding: 6px 10px;
    font-weight: 500;
}

QProgressBar {
    background-color: #334155;
    border-radius: 4px;
    text-align: center;
    color: #ffffff;
    font-size: 11px;
    font-weight: 600;
    height: 14px;
}

QProgressBar::chunk {
    background-color: #38bdf8;
    border-radius: 4px;
}

QTableWidget {
    background-color: #1e293b;
    border: 1px solid #334155;
    border-radius: 6px;
    gridline-color: #334155;
    color: #f8fafc;
}

QTableWidget::item {
    padding: 4px 8px;
    border-bottom: 1px solid #334155;
}

QTableWidget::item:selected {
    background-color: #0284c7;
}

QHeaderView::section {
    background-color: #0f172a;
    color: #94a3b8;
    padding: 6px;
    border: none;
    border-bottom: 1px solid #334155;
    font-weight: 600;
    font-size: 12px;
}

QCheckBox {
    color: #f8fafc;
    spacing: 8px;
}

QCheckBox::indicator {
    width: 18px;
    height: 18px;
    border-radius: 4px;
    border: 1px solid #475569;
    background-color: #0f172a;
}

QCheckBox::indicator:checked {
    background-color: #0284c7;
    border: 1px solid #38bdf8;
}

QMenu {
    background-color: #1e293b;
    color: #f8fafc;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 4px;
}

QMenu::item {
    padding: 8px 24px;
    border-radius: 4px;
}

QMenu::item:selected {
    background-color: #0284c7;
}

QMenu::separator {
    height: 1px;
    background-color: #334155;
    margin: 4px 8px;
}
"""

# ---------- Main GUI Window ----------
class AgentMainWindow(QMainWindow):
    def __init__(self, server_mgr: AgentServerManager):
        super().__init__()
        self.server_mgr = server_mgr
        self.has_notified_tray = False
        self.activity_logs = []
        self.setWindowTitle("LAN Monitor Agent")
        self.setWindowIcon(get_app_icon())
        self.setMinimumSize(620, 640)
        self.resize(640, 680)
        self.setStyleSheet(DARK_STYLE)

        self._setup_ui()
        self._setup_system_tray()
        self._setup_signals()

        # Telemetry refresh timer (every 2 seconds)
        self.metric_timer = QTimer(self)
        self.metric_timer.timeout.connect(self._refresh_system_metrics)
        self.metric_timer.start(2000)
        self._refresh_system_metrics()

    def _setup_ui(self):
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QVBoxLayout(main_widget)
        main_layout.setContentsMargins(16, 16, 16, 16)
        main_layout.setSpacing(12)

        # Header bar
        header_layout = QHBoxLayout()
        header_layout.setSpacing(12)

        app_icon_lbl = QLabel()
        app_icon_lbl.setPixmap(get_app_icon().pixmap(36, 36))
        header_layout.addWidget(app_icon_lbl)

        title_layout = QVBoxLayout()
        title_layout.setSpacing(2)
        title_lbl = QLabel("LAN Monitor Agent")
        title_lbl.setProperty("class", "title")
        title_layout.addWidget(title_lbl)

        ver_lbl = QLabel(f"Phiên bản {VERSION} • Máy chủ thu thập thông số ngầm")
        ver_lbl.setProperty("class", "subtitle")
        title_layout.addWidget(ver_lbl)
        header_layout.addLayout(title_layout)

        header_layout.addStretch()

        # Running Status Badge
        self.status_badge = QLabel("● Đang chạy")
        self.status_badge.setStyleSheet(
            "background-color: #064e3b; color: #34d399; font-weight: 700; "
            "padding: 6px 12px; border-radius: 12px; border: 1px solid #059669;"
        )
        header_layout.addWidget(self.status_badge)

        main_layout.addLayout(header_layout)

        # Tabs
        self.tabs = QTabWidget()
        self.tab_overview = QWidget()
        self.tab_settings = QWidget()
        self.tab_logs = QWidget()

        self._build_overview_tab()
        self._build_settings_tab()
        self._build_logs_tab()

        self.tabs.addTab(self.tab_overview, "🌐 Tổng quan & Mạng")
        self.tabs.addTab(self.tab_settings, "⚙ Cài đặt & Bảo mật")
        self.tabs.addTab(self.tab_logs, "📋 Nhật ký hoạt động")
        main_layout.addWidget(self.tabs, stretch=1)

        # Bottom Bar
        bottom_layout = QHBoxLayout()
        bottom_layout.setSpacing(10)

        tray_tip_lbl = QLabel("📌 Đóng cửa sổ sẽ ẩn ứng dụng xuống khay hệ thống (System Tray).")
        tray_tip_lbl.setStyleSheet("color: #64748b; font-size: 11px;")
        bottom_layout.addWidget(tray_tip_lbl)
        bottom_layout.addStretch()

        btn_hide = QPushButton("Ẩn vào khay hệ thống")
        btn_hide.setIcon(heroicon(HEROICONS["chevron_down"], "#f8fafc", 16))
        btn_hide.clicked.connect(self.hide)
        bottom_layout.addWidget(btn_hide)

        btn_exit = QPushButton("Thoát hoàn toàn")
        btn_exit.setProperty("class", "danger")
        btn_exit.setIcon(heroicon(HEROICONS["power"], "#ffffff", 16))
        btn_exit.clicked.connect(self._confirm_exit)
        bottom_layout.addWidget(btn_exit)

        main_layout.addLayout(bottom_layout)

    # ----- Tab 1: Overview -----
    def _build_overview_tab(self):
        layout = QVBoxLayout(self.tab_overview)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)

        # Network Card
        net_card = QFrame()
        net_card.setProperty("class", "card")
        net_layout = QVBoxLayout(net_card)
        net_layout.setSpacing(8)

        net_header = QLabel("THÔNG TIN KẾT NỐI MẠNG")
        net_header.setProperty("class", "section-header")
        net_layout.addWidget(net_header)

        grid = QGridLayout()
        grid.setSpacing(8)
        grid.setColumnStretch(1, 1)

        # Hostname
        grid.addWidget(QLabel("Tên máy tính (Hostname):"), 0, 0)
        self.val_hostname = QLabel(CFG.get("name") or socket.gethostname())
        self.val_hostname.setProperty("class", "info-value")
        grid.addWidget(self.val_hostname, 0, 1)

        # Port
        grid.addWidget(QLabel("Cổng hoạt động (Port):"), 1, 0)
        self.val_port = QLabel(str(self.server_mgr.port))
        self.val_port.setProperty("class", "info-value")
        grid.addWidget(self.val_port, 1, 1)

        # LAN IP
        grid.addWidget(QLabel("IP Mạng LAN:"), 2, 0)
        self.val_lan_ip = QLabel(get_lan_ip())
        self.val_lan_ip.setProperty("class", "info-value")
        grid.addWidget(self.val_lan_ip, 2, 1)

        btn_copy_lan = QPushButton("Sao chép IP")
        btn_copy_lan.setIcon(heroicon(HEROICONS["copy"], "#94a3b8", 14))
        btn_copy_lan.clicked.connect(lambda: self._copy_to_clipboard(self.val_lan_ip.text(), btn_copy_lan, "Sao chép IP"))
        grid.addWidget(btn_copy_lan, 2, 2)

        # Tailscale IP
        grid.addWidget(QLabel("IP Tailscale (nếu có):"), 3, 0)
        ts_ip = get_tailscale_ip() or "Không phát hiện"
        self.val_ts_ip = QLabel(ts_ip)
        self.val_ts_ip.setProperty("class", "info-value")
        grid.addWidget(self.val_ts_ip, 3, 1)

        btn_copy_ts = QPushButton("Sao chép IP")
        btn_copy_ts.setIcon(heroicon(HEROICONS["copy"], "#94a3b8", 14))
        btn_copy_ts.clicked.connect(lambda: self._copy_to_clipboard(self.val_ts_ip.text(), btn_copy_ts, "Sao chép IP"))
        btn_copy_ts.setEnabled(ts_ip != "Không phát hiện")
        grid.addWidget(btn_copy_ts, 3, 2)

        # Endpoint URL
        grid.addWidget(QLabel("URL kết nối Dashboard:"), 4, 0)
        url_str = f"http://{get_lan_ip()}:{self.server_mgr.port}"
        self.val_url = QLabel(url_str)
        self.val_url.setStyleSheet("color: #38bdf8; font-weight: 600; font-family: monospace;")
        grid.addWidget(self.val_url, 4, 1)

        btn_copy_url = QPushButton("Sao chép URL")
        btn_copy_url.setIcon(heroicon(HEROICONS["copy"], "#94a3b8", 14))
        btn_copy_url.clicked.connect(lambda: self._copy_to_clipboard(self.val_url.text(), btn_copy_url, "Sao chép URL"))
        grid.addWidget(btn_copy_url, 4, 2)

        net_layout.addLayout(grid)

        # Server Toggle Bar
        action_layout = QHBoxLayout()
        action_layout.setSpacing(10)
        self.btn_toggle_server = QPushButton("Tạm dừng dịch vụ")
        self.btn_toggle_server.setIcon(heroicon(HEROICONS["pause"], "#ffffff", 16))
        self.btn_toggle_server.clicked.connect(self._toggle_server)
        action_layout.addWidget(self.btn_toggle_server)

        btn_restart = QPushButton("Khởi động lại Server")
        btn_restart.setIcon(heroicon(HEROICONS["refresh"], "#94a3b8", 16))
        btn_restart.clicked.connect(self._restart_server)
        action_layout.addWidget(btn_restart)
        action_layout.addStretch()

        net_layout.addLayout(action_layout)
        layout.addWidget(net_card)

        # Hardware Card (Live Preview)
        hw_card = QFrame()
        hw_card.setProperty("class", "card")
        hw_layout = QVBoxLayout(hw_card)
        hw_layout.setSpacing(10)

        hw_header = QLabel("TẢI HỆ THỐNG TRỰC TIẾP (LIVE MONITOR)")
        hw_header.setProperty("class", "section-header")
        hw_layout.addWidget(hw_header)

        # CPU Row
        cpu_row = QHBoxLayout()
        cpu_lbl_title = QLabel("CPU:")
        cpu_lbl_title.setFixedWidth(50)
        cpu_row.addWidget(cpu_lbl_title)
        self.bar_cpu = QProgressBar()
        self.bar_cpu.setRange(0, 100)
        cpu_row.addWidget(self.bar_cpu, stretch=1)
        self.lbl_cpu_val = QLabel("0%")
        self.lbl_cpu_val.setFixedWidth(60)
        self.lbl_cpu_val.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        cpu_row.addWidget(self.lbl_cpu_val)
        hw_layout.addLayout(cpu_row)

        # RAM Row
        ram_row = QHBoxLayout()
        ram_lbl_title = QLabel("RAM:")
        ram_lbl_title.setFixedWidth(50)
        ram_row.addWidget(ram_lbl_title)
        self.bar_ram = QProgressBar()
        self.bar_ram.setRange(0, 100)
        ram_row.addWidget(self.bar_ram, stretch=1)
        self.lbl_ram_val = QLabel("0%")
        self.lbl_ram_val.setFixedWidth(60)
        self.lbl_ram_val.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        ram_row.addWidget(self.lbl_ram_val)
        hw_layout.addLayout(ram_row)

        # DISK Row
        disk_row = QHBoxLayout()
        disk_lbl_title = QLabel("Ổ C:\\:")
        disk_lbl_title.setFixedWidth(50)
        disk_row.addWidget(disk_lbl_title)
        self.bar_disk = QProgressBar()
        self.bar_disk.setRange(0, 100)
        disk_row.addWidget(self.bar_disk, stretch=1)
        self.lbl_disk_val = QLabel("0%")
        self.lbl_disk_val.setFixedWidth(60)
        self.lbl_disk_val.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        disk_row.addWidget(self.lbl_disk_val)
        hw_layout.addLayout(disk_row)

        # Quick stats line: Net rate & Uptime
        stats_layout = QHBoxLayout()
        self.lbl_net_rate = QLabel("Mạng: ↓ 0.0 KB/s  ↑ 0.0 KB/s")
        self.lbl_net_rate.setStyleSheet("color: #94a3b8; font-size: 12px;")
        stats_layout.addWidget(self.lbl_net_rate)

        stats_layout.addStretch()

        self.lbl_uptime = QLabel("Thời gian bật: -")
        self.lbl_uptime.setStyleSheet("color: #94a3b8; font-size: 12px;")
        stats_layout.addWidget(self.lbl_uptime)

        hw_layout.addLayout(stats_layout)
        layout.addWidget(hw_card)
        layout.addStretch()

    # ----- Tab 2: Settings -----
    def _build_settings_tab(self):
        layout = QVBoxLayout(self.tab_settings)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)

        # Settings Form Card
        cfg_card = QFrame()
        cfg_card.setProperty("class", "card")
        cfg_layout = QVBoxLayout(cfg_card)
        cfg_layout.setSpacing(12)

        cfg_header = QLabel("CẤU HÌNH THÔNG SỐ AGENT")
        cfg_header.setProperty("class", "section-header")
        cfg_layout.addWidget(cfg_header)

        grid = QGridLayout()
        grid.setSpacing(10)
        grid.setColumnStretch(1, 1)

        # Machine Name
        grid.addWidget(QLabel("Tên máy hiển thị:"), 0, 0)
        self.txt_hostname = QLineEdit(CFG.get("name") or socket.gethostname())
        self.txt_hostname.setPlaceholderText("Ví dụ: PC-DIEU-HANH-01")
        grid.addWidget(self.txt_hostname, 0, 1, 1, 2)

        # Port
        grid.addWidget(QLabel("Cổng Agent (Port):"), 1, 0)
        self.spin_port = QSpinBox()
        self.spin_port.setRange(1024, 65535)
        self.spin_port.setValue(int(CFG.get("port", DEFAULT_PORT)))
        grid.addWidget(self.spin_port, 1, 1, 1, 2)

        # Token
        grid.addWidget(QLabel("Mã Secret Token:"), 2, 0)
        token_sublayout = QHBoxLayout()
        token_sublayout.setSpacing(6)

        self.txt_token = QLineEdit(str(CFG.get("token", DEFAULT_TOKEN)))
        self.txt_token.setEchoMode(QLineEdit.Password)
        token_sublayout.addWidget(self.txt_token, stretch=1)

        self.btn_eye_token = QPushButton()
        self.btn_eye_token.setIcon(heroicon(HEROICONS["eye"], "#94a3b8", 16))
        self.btn_eye_token.setToolTip("Hiện / Ẩn Token")
        self.btn_eye_token.setFixedWidth(36)
        self.btn_eye_token.clicked.connect(self._toggle_token_visibility)
        token_sublayout.addWidget(self.btn_eye_token)

        btn_rand_token = QPushButton("Tạo ngẫu nhiên")
        btn_rand_token.setIcon(heroicon(HEROICONS["key"], "#94a3b8", 14))
        btn_rand_token.clicked.connect(self._generate_random_token)
        token_sublayout.addWidget(btn_rand_token)

        btn_copy_token = QPushButton("Sao chép")
        btn_copy_token.setIcon(heroicon(HEROICONS["copy"], "#94a3b8", 14))
        btn_copy_token.clicked.connect(lambda: self._copy_to_clipboard(self.txt_token.text(), btn_copy_token, "Sao chép"))
        token_sublayout.addWidget(btn_copy_token)

        grid.addLayout(token_sublayout, 2, 1, 1, 2)
        cfg_layout.addLayout(grid)

        # Save Button
        self.btn_save_cfg = QPushButton("💾 Lưu Cấu Hình & Áp Dụng")
        self.btn_save_cfg.setProperty("class", "primary")
        self.btn_save_cfg.clicked.connect(self._save_configuration)
        cfg_layout.addWidget(self.btn_save_cfg)

        layout.addWidget(cfg_card)

        # System Integration Card
        sys_card = QFrame()
        sys_card.setProperty("class", "card")
        sys_layout = QVBoxLayout(sys_card)
        sys_layout.setSpacing(12)

        sys_header = QLabel("TÍCH HỢP HỆ THỐNG WINDOWS")
        sys_header.setProperty("class", "section-header")
        sys_layout.addWidget(sys_header)

        # Autostart checkbox
        self.chk_autostart = QCheckBox("Tự động khởi động cùng Windows (Chạy ngầm trong khay hệ thống)")
        self.chk_autostart.setChecked(is_autostart_enabled())
        self.chk_autostart.toggled.connect(self._on_autostart_toggled)
        sys_layout.addWidget(self.chk_autostart)

        # Firewall Button
        fw_box = QHBoxLayout()
        fw_box.setSpacing(10)
        btn_firewall = QPushButton("🛡 Mở cổng Firewall Windows")
        btn_firewall.setIcon(heroicon(HEROICONS["shield"], "#38bdf8", 16))
        btn_firewall.clicked.connect(self._trigger_firewall_setup)
        fw_box.addWidget(btn_firewall)

        fw_hint = QLabel("Tự động cấp quyền qua Windows Firewall cho cổng hiện tại")
        fw_hint.setStyleSheet("color: #94a3b8; font-size: 11px;")
        fw_box.addWidget(fw_hint, stretch=1)
        sys_layout.addLayout(fw_box)

        layout.addWidget(sys_card)
        layout.addStretch()

    # ----- Tab 3: Logs -----
    def _build_logs_tab(self):
        layout = QVBoxLayout(self.tab_logs)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)

        # Log Top Stats Bar
        bar_layout = QHBoxLayout()
        self.lbl_log_stats = QLabel("Tổng yêu cầu đã phục vụ: 0")
        self.lbl_log_stats.setStyleSheet("font-weight: 600; color: #f8fafc;")
        bar_layout.addWidget(self.lbl_log_stats)

        bar_layout.addStretch()

        self.chk_autoscroll = QCheckBox("Tự động cuộn")
        self.chk_autoscroll.setChecked(True)
        bar_layout.addWidget(self.chk_autoscroll)

        btn_clear_log = QPushButton("Xóa nhật ký")
        btn_clear_log.setIcon(heroicon(HEROICONS["trash"], "#94a3b8", 14))
        btn_clear_log.clicked.connect(self._clear_activity_logs)
        bar_layout.addWidget(btn_clear_log)

        layout.addLayout(bar_layout)

        # Table
        self.tbl_logs = QTableWidget()
        self.tbl_logs.setColumnCount(4)
        self.tbl_logs.setHorizontalHeaderLabels(["Thời gian", "IP Client", "Yêu cầu", "Trạng thái"])
        self.tbl_logs.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeToContents)
        self.tbl_logs.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.tbl_logs.horizontalHeader().setSectionResizeMode(2, QHeaderView.Stretch)
        self.tbl_logs.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeToContents)
        self.tbl_logs.verticalHeader().setVisible(False)
        self.tbl_logs.setSelectionBehavior(QTableWidget.SelectRows)
        self.tbl_logs.setEditTriggers(QTableWidget.NoEditTriggers)

        layout.addWidget(self.tbl_logs)

    # ----- System Tray Setup -----
    def _setup_system_tray(self):
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setIcon(get_app_icon())
        self.tray_icon.setToolTip(f"LAN Monitor Agent - Đang chạy (Port {self.server_mgr.port})")

        tray_menu = QMenu()

        act_show = tray_menu.addAction("📊 Mở Bảng Điều Khiển")
        font = act_show.font()
        font.setBold(True)
        act_show.setFont(font)
        act_show.triggered.connect(self._show_and_activate)

        tray_menu.addSeparator()

        self.act_tray_status = tray_menu.addAction(f"🟢 Trạng thái: Cổng {self.server_mgr.port}")
        self.act_tray_status.setEnabled(False)

        self.act_tray_toggle = tray_menu.addAction("⏸ Tạm dừng dịch vụ")
        self.act_tray_toggle.triggered.connect(self._toggle_server)

        tray_menu.addSeparator()

        act_copy_lan = tray_menu.addAction("📋 Sao chép IP LAN")
        act_copy_lan.triggered.connect(lambda: QApplication.clipboard().setText(get_lan_ip()))

        act_copy_token = tray_menu.addAction("📋 Sao chép Token")
        act_copy_token.triggered.connect(lambda: QApplication.clipboard().setText(str(CFG.get("token", DEFAULT_TOKEN))))

        tray_menu.addSeparator()

        self.act_tray_autostart = tray_menu.addAction("🚀 Khởi động cùng Windows")
        self.act_tray_autostart.setCheckable(True)
        self.act_tray_autostart.setChecked(is_autostart_enabled())
        self.act_tray_autostart.triggered.connect(lambda chk: self.chk_autostart.setChecked(chk))

        act_firewall = tray_menu.addAction("🛡 Mở cổng Firewall")
        act_firewall.triggered.connect(self._trigger_firewall_setup)

        tray_menu.addSeparator()

        act_exit = tray_menu.addAction("❌ Thoát Agent")
        act_exit.triggered.connect(self._confirm_exit)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self._on_tray_activated)
        self.tray_icon.show()

    def _setup_signals(self):
        signals = get_signals()
        signals.request_logged.connect(self._on_request_logged)
        signals.server_state_changed.connect(self._on_server_state_changed)

    def _on_tray_activated(self, reason):
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self._show_and_activate()

    def _show_and_activate(self):
        self.showNormal()
        self.raise_()
        self.activateWindow()

    def closeEvent(self, event):
        if self.tray_icon and self.tray_icon.isVisible():
            event.ignore()
            self.hide()
            if not self.has_notified_tray:
                self.tray_icon.showMessage(
                    "LAN Monitor Agent",
                    "Ứng dụng đang chạy ngầm trong khay hệ thống (System Tray).",
                    QSystemTrayIcon.Information,
                    2500
                )
                self.has_notified_tray = True
        else:
            event.accept()

    def _confirm_exit(self):
        reply = QMessageBox.question(
            self,
            "Xác nhận thoát",
            "Bạn có chắc chắn muốn tắt hoàn toàn LAN Monitor Agent không?\n\n"
            "Dashboard từ các máy tính khác trong mạng sẽ không thể kết nối đến máy tính này khi Agent bị tắt.",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        if reply == QMessageBox.Yes:
            self.server_mgr.stop()
            self.tray_icon.hide()
            QApplication.quit()

    # ----- Slots & Helpers -----
    def _toggle_server(self):
        if self.server_mgr.is_running:
            self.server_mgr.stop()
        else:
            self.server_mgr.start(self.spin_port.value())

    def _restart_server(self):
        port = self.spin_port.value()
        self.server_mgr.stop()
        time.sleep(0.1)
        ok, msg = self.server_mgr.start(port)
        if ok:
            QMessageBox.information(self, "Khởi động lại", f"Server đã khởi động lại thành công trên cổng {port}!")
        else:
            QMessageBox.critical(self, "Lỗi khởi động", f"Không thể khởi động Server: {msg}")

    def _on_server_state_changed(self, is_running: bool, message: str):
        if is_running:
            self.status_badge.setText(f"● Đang chạy (Port {self.server_mgr.port})")
            self.status_badge.setStyleSheet(
                "background-color: #064e3b; color: #34d399; font-weight: 700; "
                "padding: 6px 12px; border-radius: 12px; border: 1px solid #059669;"
            )
            self.btn_toggle_server.setText("Tạm dừng dịch vụ")
            self.btn_toggle_server.setIcon(heroicon(HEROICONS["pause"], "#ffffff", 16))
            self.act_tray_toggle.setText("⏸ Tạm dừng dịch vụ")
            self.act_tray_status.setText(f"🟢 Trạng thái: Cổng {self.server_mgr.port}")
            self.tray_icon.setToolTip(f"LAN Monitor Agent - Đang chạy (Port {self.server_mgr.port})")
        else:
            self.status_badge.setText("● Đã tạm dừng")
            self.status_badge.setStyleSheet(
                "background-color: #451a03; color: #fbbf24; font-weight: 700; "
                "padding: 6px 12px; border-radius: 12px; border: 1px solid #d97706;"
            )
            self.btn_toggle_server.setText("Tiếp tục dịch vụ")
            self.btn_toggle_server.setIcon(heroicon(HEROICONS["play"], "#ffffff", 16))
            self.act_tray_toggle.setText("▶ Tiếp tục dịch vụ")
            self.act_tray_status.setText("🔴 Trạng thái: Đã tạm dừng")
            self.tray_icon.setToolTip("LAN Monitor Agent - Đã tạm dừng")

    def _toggle_token_visibility(self):
        if self.txt_token.echoMode() == QLineEdit.Password:
            self.txt_token.setEchoMode(QLineEdit.Normal)
        else:
            self.txt_token.setEchoMode(QLineEdit.Password)

    def _generate_random_token(self):
        new_tok = secrets.token_hex(8)
        self.txt_token.setText(new_tok)
        self.txt_token.setEchoMode(QLineEdit.Normal)

    def _copy_to_clipboard(self, text: str, btn: QPushButton, original_text: str):
        QApplication.clipboard().setText(text)
        btn.setText("✓ Đã chép!")
        btn.setIcon(heroicon(HEROICONS["check"], "#34d399", 14))
        QTimer.singleShot(1500, lambda: self._restore_btn_copy(btn, original_text))

    def _restore_btn_copy(self, btn: QPushButton, original_text: str):
        btn.setText(original_text)
        btn.setIcon(heroicon(HEROICONS["copy"], "#94a3b8", 14))

    def _save_configuration(self):
        global CFG, PORT, TOKEN
        new_port = self.spin_port.value()
        new_name = self.txt_hostname.text().strip() or socket.gethostname()
        new_token = self.txt_token.text().strip()

        CFG["name"] = new_name
        CFG["port"] = new_port
        CFG["token"] = new_token
        PORT = new_port
        TOKEN = new_token

        if save_config(CFG):
            # Update labels
            self.val_hostname.setText(new_name)
            self.val_port.setText(str(new_port))
            self.val_url.setText(f"http://{get_lan_ip()}:{new_port}")

            # Restart if port changed
            if new_port != self.server_mgr.port:
                self.server_mgr.start(new_port)

            QMessageBox.information(self, "Lưu thành công", "Cấu hình Agent đã được lưu và cập nhật thành công!")
        else:
            QMessageBox.critical(self, "Lỗi lưu file", "Không thể ghi cấu hình vào agent_config.json")

    def _on_autostart_toggled(self, checked: bool):
        ok, msg = set_autostart(checked)
        if not ok:
            QMessageBox.warning(self, "Lỗi Autostart", f"Không thể thay đổi thiết lập khởi động cùng Windows:\n{msg}")
            # Revert checkbox without re-triggering signal
            self.chk_autostart.blockSignals(True)
            self.chk_autostart.setChecked(is_autostart_enabled())
            self.chk_autostart.blockSignals(False)
        else:
            self.act_tray_autostart.blockSignals(True)
            self.act_tray_autostart.setChecked(checked)
            self.act_tray_autostart.blockSignals(False)

    def _trigger_firewall_setup(self):
        port = self.server_mgr.port
        reply = QMessageBox.question(
            self,
            "Cấp quyền Windows Firewall",
            f"Bạn có muốn thêm quy tắc mở cổng TCP {port} trên Windows Firewall không?\n\n"
            "Hệ thống sẽ hiện hộp thoại xác nhận quyền Quản trị viên (UAC) của Windows.",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.Yes
        )
        if reply == QMessageBox.Yes:
            ok, msg = open_firewall_rule(port)
            if ok:
                QMessageBox.information(self, "Thành công", msg)
            else:
                QMessageBox.critical(self, "Lỗi Firewall", msg)

    def _refresh_system_metrics(self):
        try:
            # CPU
            cpu = psutil.cpu_percent(interval=None)
            self.bar_cpu.setValue(int(cpu))
            self.lbl_cpu_val.setText(f"{cpu:.1f}%")

            # RAM
            vm = psutil.virtual_memory()
            self.bar_ram.setValue(int(vm.percent))
            self.lbl_ram_val.setText(f"{vm.percent:.1f}%")

            # Disk
            root_path = "C:\\" if platform.system() == "Windows" else "/"
            disk = psutil.disk_usage(root_path)
            self.bar_disk.setValue(int(disk.percent))
            self.lbl_disk_val.setText(f"{disk.percent:.1f}%")

            # Network
            down, up = bytes_per_sec()
            def fmt(b):
                if b >= 1024 * 1024:
                    return f"{b / (1024*1024):.1f} MB/s"
                return f"{b / 1024:.1f} KB/s"
            self.lbl_net_rate.setText(f"Mạng: ↓ {fmt(down)}  ↑ {fmt(up)}")

            # Uptime
            boot = psutil.boot_time()
            sec = int(time.time() - boot)
            d, h, m = sec // 86400, (sec % 86400) // 3600, (sec % 3600) // 60
            if d > 0:
                upt_str = f"{d} ngày {h} giờ {m} phút"
            elif h > 0:
                upt_str = f"{h} giờ {m} phút"
            else:
                upt_str = f"{m} phút"
            self.lbl_uptime.setText(f"Thời gian bật: {upt_str}")
        except Exception:
            pass

    def _on_request_logged(self, entry: dict):
        self.server_mgr.total_requests += 1
        self.lbl_log_stats.setText(f"Tổng yêu cầu đã phục vụ: {self.server_mgr.total_requests}")

        row = self.tbl_logs.rowCount()
        self.tbl_logs.insertRow(row)

        item_time = QTableWidgetItem(entry.get("time", ""))
        item_client = QTableWidgetItem(entry.get("client", ""))
        item_req = QTableWidgetItem(f"{entry.get('method', '')} {entry.get('path', '')} ({entry.get('detail', '')})")
        
        status_code = entry.get("status", 200)
        item_status = QTableWidgetItem(str(status_code))
        if status_code == 200:
            item_status.setForeground(QColor("#34d399")) # Emerald
        elif status_code == 401:
            item_status.setForeground(QColor("#f87171")) # Rose / Red
        else:
            item_status.setForeground(QColor("#fbbf24")) # Amber

        self.tbl_logs.setItem(row, 0, item_time)
        self.tbl_logs.setItem(row, 1, item_client)
        self.tbl_logs.setItem(row, 2, item_req)
        self.tbl_logs.setItem(row, 3, item_status)

        # Limit to 200 rows
        if self.tbl_logs.rowCount() > 200:
            self.tbl_logs.removeRow(0)

        if self.chk_autoscroll.isChecked():
            self.tbl_logs.scrollToBottom()

    def _clear_activity_logs(self):
        self.tbl_logs.setRowCount(0)

# ---------- Application Entry Point ----------
def main():
    # Windows taskbar icon app model ID
    if platform.system() == "Windows":
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(f"LANMonitor.Agent.{VERSION}")
        except Exception:
            pass

    app = QApplication(sys.argv)
    app.setApplicationName("LANMonitorAgent")
    app.setQuitOnLastWindowClosed(False)  # Keep running in tray when window is closed

    server_mgr = AgentServerManager()
    ok, msg = server_mgr.start(PORT)
    if not ok:
        print(f"[CẢNH BÁO] Không thể khởi động server trên cổng {PORT}: {msg}")

    window = AgentMainWindow(server_mgr)

    # Check CLI flags: if --tray or --minimized, start hidden in system tray
    start_in_tray = "--tray" in sys.argv or "--minimized" in sys.argv
    if not start_in_tray:
        window.show()

    sys.exit(app.exec())

if __name__ == "__main__":
    main()
