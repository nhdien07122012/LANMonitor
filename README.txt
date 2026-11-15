
# LAN Monitor – Agent + Dashboard cho Windows

## 1. Mục đích
Giám sát nhiều PC trong cùng mạng LAN mà không cần Remote Desktop.

Dashboard hiển thị:
- CPU %
- RAM %
- GPU utilization + tên GPU + VRAM (NVIDIA nếu có nvidia-smi)
- Download / Upload theo giây
- Disk C:
- Nhiệt độ GPU NVIDIA nếu có
- Nhiệt độ cảm biến mà Windows/psutil cung cấp (nếu có)
- Uptime
- Online / Offline
- Cập nhật khoảng 1.5 giây

## 2. Cấu trúc
- agent.py: chương trình chạy trên MÁY CẦN GIÁM SÁT.
- dashboard.py: chương trình chạy trên MÁY QUẢN LÝ.
- agent_config.example.json: cấu hình Agent.
- dashboard_config.example.json: cấu hình Dashboard.
- build_windows.bat: build 2 file EXE.
- firewall_agent.bat: mở TCP 8765 trên Windows Firewall.
- start_agent.bat: chạy Agent.

## 3. Build trên Windows
Cài Python 3.11/3.12/3.13, sau đó mở CMD trong thư mục này:

    build_windows.bat

Sau khi xong:
    dist\LANMonitorAgent.exe
    dist\LANMonitorDashboard.exe

## 4. Cài Agent trên máy đích
Copy các file sau vào một thư mục, ví dụ C:\LANMonitorAgent\:
    LANMonitorAgent.exe
    agent_config.example.json

Đổi:
    agent_config.example.json
thành:
    agent_config.json

Sửa token:
    "token": "MẬT_KHẨU_CỦA_BẠN"

Sửa name:
    "name": "SRO130"

Nếu dùng port mặc định thì giữ:
    "port": 8765

Chạy:
    firewall_agent.bat
    LANMonitorAgent.exe

## 5. Thêm máy vào Dashboard
Chạy LANMonitorDashboard.exe.

Bấm "+ Thêm máy":
- IP: IP LAN của máy đích, ví dụ 192.168.1.4
- Tên: SRO130
- Port: 8765

Token trong Dashboard phải giống token trong Agent.

## 6. Test nhanh
Trên máy quản lý có thể mở CMD:
    ping 192.168.1.4

Sau đó chạy Dashboard.

Nếu ping được nhưng Dashboard báo OFFLINE:
- kiểm tra Agent đang chạy
- kiểm tra port 8765
- kiểm tra Windows Firewall
- kiểm tra token
- thử mở:
  http://192.168.1.4:8765/health

## 7. Tự chạy Agent khi Windows khởi động
Đơn giản nhất:
- Win + R
- gõ shell:startup
- tạo shortcut tới LANMonitorAgent.exe

Nếu muốn chạy ẩn hoàn toàn, có thể tạo Scheduled Task chạy với quyền SYSTEM hoặc dùng bản build --noconsole.

## 8. Lưu ý nhiệt độ
Windows/psutil không đảm bảo đọc được nhiệt độ CPU trên mọi mainboard/laptop.
GPU NVIDIA đọc được qua nvidia-smi nếu driver NVIDIA hỗ trợ.
Nếu cần CPU temperature chính xác trên nhiều máy, có thể bổ sung LibreHardwareMonitor ở phiên bản 2.

## 9. Bảo mật
Agent chỉ nên mở trong mạng LAN tin cậy.
Token mặc định cần đổi trước khi sử dụng thật.
Không forward port 8765 ra Internet.
