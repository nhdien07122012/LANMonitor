#!/usr/bin/env python3
"""
LAN Monitor Agent for Linux / Armbian (Headless / Service)
Tương thích hoàn toàn với LANMonitor Dashboard và iOS App.
Tối ưu hóa siêu nhẹ (<15MB RAM), không cần thư viện GUI (PySide6/Qt).
"""

import sys
import os
import time
import json
import socket
import platform
import subprocess
import threading
import signal
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

try:
    import psutil
except ImportError:
    print("[LỖI] Chưa cài đặt psutil! Vui lòng chạy: sudo apt install python3-psutil")
    sys.exit(1)

VERSION = "1.1.0-linux"
DEFAULT_PORT = 8765
DEFAULT_TOKEN = "LANMONITOR-CHANGE-ME"

# ---------- Config Helpers ----------
def get_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

def get_config_path() -> Path:
    # Ưu tiên file trong thư mục hiện tại, fallback về /etc/lanmonitor/
    local_cfg = get_base_dir() / "agent_config.json"
    if local_cfg.exists():
        return local_cfg
    etc_cfg = Path("/etc/lanmonitor/agent_config.json")
    if etc_cfg.exists():
        return etc_cfg
    return local_cfg

def load_config() -> dict:
    cfg = {
        "port": DEFAULT_PORT,
        "token": DEFAULT_TOKEN,
        "name": socket.gethostname(),
        "interval": 1.0,
    }
    path = get_config_path()
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            cfg.update(data)
        except Exception as e:
            print(f"[CẢNH BÁO] Không thể đọc file cấu hình {path}: {e}")
    return cfg

CFG = load_config()
PORT = int(CFG.get("port", DEFAULT_PORT))
TOKEN = str(CFG.get("token", DEFAULT_TOKEN))
HOSTNAME = str(CFG.get("name", socket.gethostname()))

# ---------- Metrics Helpers ----------
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
    # Kiểm tra nvidia-smi nếu là máy Linux có card rời NVIDIA
    result = []
    try:
        p = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2
        )
        if p.returncode == 0:
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

    # Fallback cho Armbian / SoC ARM (Amlogic, Allwinner, Rockchip, Raspberry Pi)
    if not out and os.path.exists("/sys/class/thermal/thermal_zone0/temp"):
        try:
            with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                val = float(f.read().strip())
                if val > 1000:
                    val = val / 1000.0
                out["cpu-thermal"] = round(val, 1)
        except Exception:
            pass
    return out

def get_lan_ip():
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
    try:
        addrs = psutil.net_if_addrs()
        # 1. Tìm card mạng tên chứa 'tailscale'
        for iface_name, iface_addrs in addrs.items():
            if "tailscale" in iface_name.lower():
                for addr in iface_addrs:
                    if addr.family == socket.AF_INET:
                        return addr.address
        # 2. Tìm dải CGNAT của Tailscale (100.64.0.0/10)
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
    try:
        disk = psutil.disk_usage("/")
    except Exception:
        class DiskMock:
            percent = 0
            free = 0
        disk = DiskMock()
    boot = psutil.boot_time()
    gpus = gpu_info()
    return {
        "version": VERSION,
        "hostname": CFG.get("name") or HOSTNAME,
        "ip": get_lan_ip(),
        "tailscale_ip": get_tailscale_ip(),
        "timestamp": time.time(),
        "cpu_percent": round(psutil.cpu_percent(interval=0.15), 1),
        "cpu_count": psutil.cpu_count(logical=True) or 1,
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

# ---------- HTTP Request Handler ----------
class LinuxAgentHTTPHandler(BaseHTTPRequestHandler):
    server_version = f"LANMonitorAgentLinux/{VERSION}"

    def log_message(self, fmt, *args):
        # Xuất log ra console gọn gàng cho journalctl / systemd
        client_ip = self.client_address[0] if self.client_address else "Unknown"
        sys.stdout.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {client_ip} - {fmt % args}\n")
        sys.stdout.flush()

    def send_json(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-LAN-Monitor-Token")
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            pass

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-LAN-Monitor-Token")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(200, {
                "ok": True,
                "version": VERSION,
                "hostname": CFG.get("name") or HOSTNAME
            })
            return

        if parsed.path != "/metrics":
            self.send_json(404, {"ok": False, "error": "Not found"})
            return

        # Kiểm tra Token
        token = self.headers.get("X-LAN-Monitor-Token", "")
        if TOKEN and token != TOKEN:
            self.send_json(401, {"ok": False, "error": "Unauthorized (Sai token)"})
            return

        try:
            data = snapshot()
            self.send_json(200, data)
        except Exception as e:
            self.send_json(500, {"ok": False, "error": str(e)})

    def do_POST(self):
        token = self.headers.get("X-LAN-Monitor-Token", "")
        if TOKEN and token != TOKEN:
            self.send_json(401, {"ok": False, "error": "Unauthorized (Sai token)"})
            return

        parsed = urlparse(self.path)
        if parsed.path != "/control":
            self.send_json(404, {"ok": False, "error": "Not found"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode("utf-8"))
            action = data.get("action")

            if action == "shutdown":
                self.send_json(200, {"ok": True, "message": "Đang tắt hệ thống Linux..."})
                subprocess.Popen(["systemctl", "poweroff"])
            elif action == "reboot":
                self.send_json(200, {"ok": True, "message": "Đang khởi động lại Linux..."})
                subprocess.Popen(["systemctl", "reboot"])
            elif action == "run_app":
                app_path = data.get("app_path")
                if not app_path:
                    self.send_json(400, {"ok": False, "error": "Thiếu app_path"})
                    return
                subprocess.Popen(app_path, shell=True)
                self.send_json(200, {"ok": True, "message": f"Đã thực thi lệnh: {app_path}"})
            else:
                self.send_json(400, {"ok": False, "error": f"Lệnh không hỗ trợ: {action}"})
        except Exception as e:
            self.send_json(500, {"ok": False, "error": str(e)})

# ---------- Main Execution ----------
def main():
    print(f"=== LAN Monitor Linux Agent v{VERSION} ===")
    print(f"Hostname: {HOSTNAME}")
    print(f"Port: {PORT}")
    print(f"IP LAN: {get_lan_ip()}")
    print(f"IP Tailscale: {get_tailscale_ip() or 'Chưa phát hiện'}")

    server = ThreadingHTTPServer(("0.0.0.0", PORT), LinuxAgentHTTPHandler)
    server.daemon_threads = True

    def handle_signal(sig, frame):
        print("\n[INFO] Nhận tín hiệu dừng dịch vụ, đang thoát...")
        threading.Thread(target=server.shutdown, daemon=True).start()
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    print(f"[OK] Agent đang lắng nghe tại http://0.0.0.0:{PORT}")
    print("[OK] Sẵn sàng phục vụ yêu cầu từ Dashboard...")
    try:
        server.serve_forever()
    except Exception as e:
        print(f"[LỖI] Dịch vụ dừng do ngoại lệ: {e}")

if __name__ == "__main__":
    main()
