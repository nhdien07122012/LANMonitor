
import json, os, threading, time, urllib.request, urllib.error
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog

APP_TITLE = "LAN Monitor Dashboard"
DEFAULT_PORT = 8765
DEFAULT_TOKEN = "LANMONITOR-CHANGE-ME"
REFRESH_MS = 1500

CONFIG_PATH = Path("dashboard_config.json")

def load_config():
    default = {
        "token": DEFAULT_TOKEN,
        "hosts": [
            {"name": "SRO130", "ip": "192.168.1.4", "port": DEFAULT_PORT, "enabled": True}
        ]
    }
    if CONFIG_PATH.exists():
        try:
            default.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except Exception:
            pass
    return default

def save_config(cfg):
    CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")

def fmt_rate(bps):
    units = ["B/s", "KB/s", "MB/s", "GB/s"]
    x = float(bps or 0)
    for u in units:
        if x < 1024 or u == units[-1]:
            return f"{x:.1f} {u}"
        x /= 1024

def fmt_uptime(sec):
    sec = int(sec or 0)
    d, sec = divmod(sec, 86400)
    h, sec = divmod(sec, 3600)
    m, s = divmod(sec, 60)
    return f"{d}d {h:02}:{m:02}:{s:02}" if d else f"{h:02}:{m:02}:{s:02}"

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("1180x650")
        self.minsize(900, 500)
        self.cfg = load_config()
        self.results = {}
        self.busy = False

        style = ttk.Style(self)
        try:
            style.theme_use("vista")
        except Exception:
            pass

        self.build()
        self.refresh()

    def build(self):
        top = ttk.Frame(self, padding=10)
        top.pack(fill="x")
        ttk.Label(top, text=APP_TITLE, font=("Segoe UI", 18, "bold")).pack(side="left")
        self.status = ttk.Label(top, text="Đang khởi động...")
        self.status.pack(side="right")

        bar = ttk.Frame(self, padding=(10, 0, 10, 8))
        bar.pack(fill="x")
        ttk.Button(bar, text="+ Thêm máy", command=self.add_host).pack(side="left", padx=3)
        ttk.Button(bar, text="Sửa máy", command=self.edit_host).pack(side="left", padx=3)
        ttk.Button(bar, text="Xóa máy", command=self.delete_host).pack(side="left", padx=3)
        ttk.Button(bar, text="Token", command=self.change_token).pack(side="left", padx=3)
        ttk.Button(bar, text="Làm mới ngay", command=self.refresh).pack(side="left", padx=3)

        cols = ("name","ip","status","cpu","ram","gpu","down","up","disk","temp","uptime")
        self.tree = ttk.Treeview(self, columns=cols, show="headings", height=22)
        headings = {
            "name":"Máy", "ip":"IP", "status":"Trạng thái", "cpu":"CPU",
            "ram":"RAM", "gpu":"GPU", "down":"Download", "up":"Upload",
            "disk":"Disk C:", "temp":"Nhiệt độ", "uptime":"Uptime"
        }
        widths = {"name":120,"ip":115,"status":90,"cpu":70,"ram":70,"gpu":150,"down":100,"up":100,"disk":80,"temp":100,"uptime":110}
        for c in cols:
            self.tree.heading(c, text=headings[c])
            self.tree.column(c, width=widths[c], anchor="center")
        self.tree.pack(fill="both", expand=True, padx=10, pady=(0,10))

        bottom = ttk.Label(self, text="Agent mặc định: cổng 8765 • Dashboard tự lưu danh sách máy vào dashboard_config.json", padding=8)
        bottom.pack(fill="x")

    def add_host(self):
        ip = simpledialog.askstring("Thêm máy", "IP máy đích (ví dụ 192.168.1.4):", parent=self)
        if not ip:
            return
        name = simpledialog.askstring("Tên máy", "Tên hiển thị:", initialvalue=ip, parent=self) or ip
        port = simpledialog.askinteger("Cổng Agent", "Port:", initialvalue=DEFAULT_PORT, minvalue=1, maxvalue=65535, parent=self)
        if not port:
            return
        self.cfg["hosts"].append({"name":name, "ip":ip, "port":port, "enabled":True})
        save_config(self.cfg)
        self.refresh()

    def selected_index(self):
        sel = self.tree.selection()
        if not sel:
            messagebox.showinfo("LAN Monitor", "Hãy chọn một máy trước.")
            return None
        return int(sel[0])

    def edit_host(self):
        idx = self.selected_index()
        if idx is None: return
        h = self.cfg["hosts"][idx]
        name = simpledialog.askstring("Sửa máy", "Tên:", initialvalue=h["name"], parent=self)
        if name is None: return
        ip = simpledialog.askstring("Sửa máy", "IP:", initialvalue=h["ip"], parent=self)
        if ip is None: return
        port = simpledialog.askinteger("Sửa máy", "Port:", initialvalue=h.get("port",DEFAULT_PORT), minvalue=1, maxvalue=65535, parent=self)
        if not port: return
        h.update({"name":name,"ip":ip,"port":port})
        save_config(self.cfg)
        self.refresh()

    def delete_host(self):
        idx = self.selected_index()
        if idx is None: return
        h = self.cfg["hosts"][idx]
        if messagebox.askyesno("Xóa máy", f"Xóa {h['name']} ({h['ip']})?", parent=self):
            self.cfg["hosts"].pop(idx)
            save_config(self.cfg)
            self.refresh()

    def change_token(self):
        old = simpledialog.askstring("Token", "Nhập token mới dùng chung cho Agent và Dashboard:", initialvalue=self.cfg.get("token",""), parent=self)
        if old is not None and old.strip():
            self.cfg["token"] = old.strip()
            save_config(self.cfg)
            messagebox.showinfo("LAN Monitor", "Đã lưu token cho Dashboard. Hãy đặt cùng token trong agent_config.json trên các máy đích.")

    def fetch_one(self, idx, host):
        url = f"http://{host['ip']}:{host.get('port',DEFAULT_PORT)}/metrics"
        req = urllib.request.Request(url, headers={"X-LAN-Monitor-Token": self.cfg.get("token","")})
        try:
            with urllib.request.urlopen(req, timeout=1.2) as r:
                data = json.loads(r.read().decode("utf-8"))
            self.results[idx] = (True, data, "")
        except Exception as e:
            self.results[idx] = (False, None, str(e))
        self.after(0, lambda: self.render_row(idx))

    def refresh(self):
        if self.busy:
            return
        self.busy = True
        self.status.config(text="Đang kiểm tra...")
        for i, h in enumerate(self.cfg.get("hosts", [])):
            if h.get("enabled", True):
                threading.Thread(target=self.fetch_one, args=(i,h), daemon=True).start()
        self.after(REFRESH_MS, self.refresh)
        self.busy = False

    def render_row(self, idx):
        hosts = self.cfg.get("hosts", [])
        if idx >= len(hosts): return
        h = hosts[idx]
        ok, d, err = self.results.get(idx, (False,None,""))
        vals = [h["name"], h["ip"]]
        if not ok:
            vals += ["OFFLINE", "-", "-", "-", "-", "-", "-", "-", "-", "-"]
        else:
            gpus = d.get("gpu") or []
            gpu = ", ".join(f"{g['name']} {g.get('util','-')}%" for g in gpus) if gpus else "N/A"
            temps = d.get("temperatures") or {}
            gtemp = gpus[0].get("temp_c") if gpus else None
            temp_text = f"GPU {gtemp:.0f}°C" if gtemp is not None else (", ".join(f"{k}:{v:.0f}°C" for k,v in temps.items()) if temps else "N/A")
            vals += [
                "ONLINE",
                f"{d.get('cpu_percent',0):.0f}%",
                f"{d.get('ram_percent',0):.0f}%",
                gpu[:28],
                fmt_rate(d.get("download_bps",0)),
                fmt_rate(d.get("upload_bps",0)),
                f"{d.get('disk_percent',0):.0f}%",
                temp_text,
                fmt_uptime(d.get("uptime_sec",0))
            ]
        iid = str(idx)
        if self.tree.exists(iid):
            self.tree.item(iid, values=vals)
        else:
            self.tree.insert("", "end", iid=iid, values=vals)
        self.status.config(text=f"Cập nhật {time.strftime('%H:%M:%S')}")

if __name__ == "__main__":
    App().mainloop()
