# 📋 Nhật ký thay đổi (Changelog) - LAN Monitor

Tài liệu này ghi lại toàn bộ lịch sử phát triển, các phiên bản phát hành, chi tiết kỹ thuật và lệnh rollback khẩn cấp cho từng phiên bản theo đúng quy chuẩn dự án tại `PROJECT_RULES.md`.

---

## [v1.1.6] - 2026-11-16 (Build 16)
- **Mục tiêu thay đổi**: Khắc phục triệt để lỗi crash ứng dụng khi khởi động trên iPhone. Loại bỏ thao tác force unwrap (`as!`) `rootViewController` trong `AppDelegate.swift`, hoàn tất khôi phục thông tin cấu hình máy chủ mặc định (LAN & Tailscale) và loại bỏ cơ chế xóa nhầm thiết bị khi tải app. Sửa lỗi thanh tiến trình Widget không hiển thị bằng cách xây dựng lại thanh bar bằng `GeometryReader` độc lập tương thích mọi phiên bản iOS (iOS 15 đến iOS 26+).
- **Commit SHA**: `d6a5203`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert d6a5203 --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/patch_app_delegate.py`:
    - Chuyển `rootVC as! FlutterViewController` thành `rootVC as? FlutterViewController` (optional binding an toàn), gọi sau `super.application` để đảm bảo `FlutterEngine` và `UIWindow` đã sẵn sàng, loại bỏ hoàn toàn lỗi crash SIGTRAP khi vừa nhấn mở app.
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Khôi phục cấu hình thiết bị mặc định với IP LAN (`192.168.1.4:8765`) và IP Tailscale (`100.66.18.111:8765`) kèm Token `LANMONITOR-CHANGE-ME`.
    - Loại bỏ lệnh xóa tự động `removeWhere` gây mất thông tin máy tính khi người dùng mở lại app.
  - `ios_app/lib/models/host_model.dart`:
    - Bổ sung `cleanIp`: tự động chuẩn hóa địa chỉ IP (loại bỏ `http://`, `https://`, dấu gạch chéo `/`, port trùng lặp, khoảng trắng thừa) để tránh lỗi URL không hợp lệ khi kết nối API.
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Thay thế `ProgressView` hệ thống bằng custom `GeometryReader` + `RoundedRectangle` bar 5pt bo góc, đảm bảo hiển thị thanh đo tiến trình CPU, RAM, Ổ đĩa sắc nét, không bị thu nhỏ hoặc mất thanh trên iOS 15 - iOS 26+.
    - Khôi phục thông số IP mặc định an toàn trong `loadLocalCache()` để Widget có thể truy vấn PC ngay cả khi chưa mở app lần đầu.
    - Bổ sung hàm `cleanIpAddress` lọc sạch chuỗi IP trước khi gửi request.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Đồng bộ nâng phiên bản lên `v1.1.6` (Build `16`).

---

## [v1.1.5] - 2026-11-16 (Build 15)
- **Mục tiêu thay đổi**: Khắc phục triệt để vấn đề Widget không đồng bộ dữ liệu với PC. Áp dụng kiến trúc Direct Network Fetching độc lập (theo mô hình hoạt động của Gas Manager), cấp quyền `NSAppTransportSecurity` (`NSAllowsArbitraryLoads`) cho Widget Extension, hỗ trợ Widget tự động truy vấn HTTP trực tiếp tới PC Agent theo chu kỳ 1 phút, tự động chuyển vùng dự phòng giữa IP LAN và IP Tailscale.
- **Commit SHA**: `009fe41`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 009fe41 --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Bổ sung cấu trúc `AgentMetricsResponse: Codable` giải mã trực tiếp dữ liệu phần cứng (`cpu_percent`, `ram_percent`, `disk_percent`, `download_bps`, `upload_bps`, `uptime_sec`, `hostname`, `ip`, `tailscale_ip`) từ endpoint `http://<ip>:<port>/metrics` của PC Agent.
    - Cài đặt hàm `fetchLiveMetrics` & `executeMetricRequest` sử dụng `URLSession` độc lập với timeout 3.5s, kèm header `X-LAN-Monitor-Token`.
    - Hỗ trợ cơ chế Fallback thông minh: Thử kết nối IP LAN trước, nếu mất kết nối hoặc ở ngoài nhà sẽ tự động thử kết nối IP Tailscale.
    - Tự động ghi nhớ và lưu trữ đệm (`saveCache`) dữ liệu mới nhất vào App Group UserDefaults và `widget_data.json`.
    - `getTimeline()`: Yêu cầu WidgetKit làm mới dữ liệu độc lập sau mỗi 1 phút (`policy: .after(nextDate)`).
  - `ios_app/LANMonitorWidget/Info.plist` & `ios_app/ios_widget/Info.plist`:
    - Cấp quyền `NSAppTransportSecurity` với `NSAllowsArbitraryLoads = true` cho Widget Extension, cho phép WidgetKit gửi HTTP request nội bộ trong mạng LAN (`192.168.x.x`) và mạng VPN Tailscale (`100.x.x.x`).
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Truyền thêm `tailscaleIp`, `port`, và `token` của máy chủ chính sang native widget qua MethodChannel và SharedPreferences.
  - `ios_app/patch_app_delegate.py`:
    - Tối ưu luồng đăng ký MethodChannel `com.lanmonitor/widget`, đồng bộ dữ liệu sang cả hai nhóm App Group (`group.com.lanmonitor.lanMonitor` và `group.com.lanmonitor.app`) và ghi tệp JSON shared container.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `.github/workflows/build_ios.yml`:
    - Nâng phiên bản đồng bộ lên `v1.1.5` (Build `15`).

---

## [v1.1.4] - 2026-11-16 (Build 14)
- **Mục tiêu thay đổi**: Khắc phục triệt để lỗi Widget báo online nhưng các thanh tiến trình không chạy (hiển thị 0%). Sửa lỗi đăng ký MethodChannel native trong `AppDelegate.swift`, bổ sung cơ chế đồng bộ kép đa tầng (App Group UserDefaults + file `widget_data.json` trong Shared Container), loại bỏ trạng thái Online giả lập khi chưa có dữ liệu đồng bộ từ ứng dụng.
- **Commit SHA**: `fbcef95`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert fbcef95 --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/patch_app_delegate.py`:
    - Gọi `super.application(...)` trước khi lấy `window?.rootViewController` để đảm bảo `FlutterViewController` đã được khởi tạo hoàn chỉnh, giúp `FlutterMethodChannel(name: "com.lanmonitor/widget")` nhận được lệnh và thực thi 100%.
    - Bổ sung cơ chế ghi kép: Vừa lưu vào `UserDefaults(suiteName: "group.com.lanmonitor.lanMonitor")` và `UserDefaults(suiteName: "group.com.lanmonitor.app")`, vừa ghi trực tiếp tệp `widget_data.json` vào thư mục Shared Container của App Group.
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift`:
    - Xây dựng bộ nạp đa tầng: App Group UserDefaults ➔ `widget_data.json` container ➔ standard UserDefaults fallback.
    - Loại bỏ cờ `isOnline = true` mặc định khi chưa từng nhận được dữ liệu đồng bộ; hiển thị thông báo "Chờ đồng bộ - Mở app để đồng bộ" thay vì báo Online giả lập kèm chỉ số 0%.
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Kích hoạt đồng bộ thông tin máy chủ chính cho Widget ngay trong `_loadFromPrefs()` để Widget nhận dữ liệu tức thì khi mở app.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Nâng phiên bản đồng bộ lên `v1.1.4` (Build `14`).

---

## [v1.1.3] - 2026-11-16 (Build 13)
- **Mục tiêu thay đổi**: Khắc phục triệt để lỗi Widget giữ dữ liệu cũ và đứng im khi ứng dụng mất kết nối máy chủ. Bổ sung cơ chế xử lý ngắt kết nối đa tầng: hiển thị trạng thái "Mất kết nối" kèm chấm đỏ cảnh báo, tự động reset các thanh chỉ số phần cứng về "--", hỗ trợ đồng bộ thời gian thực qua native App Group (`WidgetCenter.shared.reloadAllTimelines`) và cơ chế phát hiện timeout tự động độc lập (`secondsAgo > 300`).
- **Commit SHA**: `7817720`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 7817720 --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Tạo hàm `_syncWidget(...)` và `_syncPrimaryHostToWidget()` đồng bộ trạng thái host chính cho Widget.
    - Trong `refreshAll()`: Khi host online, gửi thông số phần cứng mới nhất; khi host offline hoặc có lỗi mạng trong block `catch (e)`, lập tức gửi `isOnline: false`, `status: "Mất kết nối"`, reset các thanh tốc độ mạng và uptime về `"--"`.
    - Tích hợp `MethodChannel('com.lanmonitor/widget')` gọi native iOS cập nhật thẳng vào App Group và yêu cầu WidgetKit reload tức thì.
    - Cập nhật `deleteHost()` và `clearMockHosts()` đồng bộ lại Widget khi danh sách thiết bị thay đổi.
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift`:
    - Bổ sung màu trạng thái `onlineColor` (Emerald `#10B981`) và `offlineColor` (Red `#EF4444`) vào `WidgetTheme`.
    - Trong `createDefaultEntry()`: Kiểm tra `widget_is_online` và timestamp `widget_last_updated`. Nếu `!isOnline` hoặc dữ liệu cũ quá 5 phút (`nowMs - lastUpdatedMs > 300000`), tự động chuyển sang trạng thái "Mất kết nối", đổi chấm sang màu đỏ, hiển thị `"--"` cho CPU, RAM, Disk, Uptime và tốc độ mạng.
    - `MetricBar`: Nhận tham số `isOnline: Bool`, làm mờ (dimmed) thanh tiến trình và hiển thị `"--"` khi mất kết nối.
    - `SmallWidgetView` & `MediumWidgetView`: Hiển thị chấm đỏ cảnh báo `#EF4444`, text "Mất kết nối" nổi bật, icon máy tính chuyển sang màu đỏ khi offline.
    - `getTimeline()`: Tối ưu chu kỳ refresh (3 phút khi online, 1 phút khi offline để phục hồi nhanh).
  - `.github/workflows/build_ios.yml`:
    - Bổ sung bước inject native code vào `AppDelegate.swift` tiếp nhận MethodChannel `com.lanmonitor/widget`, ghi vào `UserDefaults(suiteName: "group.com.lanmonitor.lanMonitor")` và gọi `WidgetCenter.shared.reloadAllTimelines()`.
    - Cập nhật target release lên `v1.1.3`.
  - `ios_app/pubspec.yaml`: Nâng phiên bản lên `1.1.3+13`.
  - `ios_app/configure_widget_target.rb`: Cập nhật `MARKETING_VERSION = '1.1.3'`, `CURRENT_PROJECT_VERSION = '13'`.
  - `ios_app/LANMonitorWidget/Info.plist`: Cập nhật `CFBundleShortVersionString = 1.1.3`, `CFBundleVersion = 13`.
  - `ios_app/ios_widget/`: Đồng bộ các tệp mã nguồn widget tương ứng.

---

## [v1.1.2] - 2026-11-16 (Build 12)
- **Mục tiêu thay đổi**: Bổ sung hỗ trợ đầy đủ giao diện Light Mode (chế độ sáng) và Dark Mode (chế độ tối) tự động cho iOS Home Screen Widget, đồng bộ màu sắc sắc nét theo đúng palette giao diện của ứng dụng Flutter; tích hợp bộ quy chuẩn `PROJECT_RULES.md`.
- **Commit SHA**: `2c8d7df`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 2c8d7df --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift`:
    - Tạo cấu trúc `WidgetTheme` quản lý 2 bộ màu Light Mode (`#F8FAFC` background, `#0F172A` text, Sky 600, Amber 600, Emerald 600) và Dark Mode (`#0F172A` background, `#F8FAFC` text, Sky 400, Amber 400, Emerald 400).
    - Lấy `@Environment(\.colorScheme) var colorScheme` trong `LANMonitorWidgetEntryView` và truyền vào `SmallWidgetView`, `MediumWidgetView`.
    - Cập nhật `MetricBar` nhận `tintColor` và `labelColor` tương phản cao theo từng chế độ sáng/tối.
  - `ios_app/pubspec.yaml`: Nâng phiên bản lên `1.1.2+12`.
  - `ios_app/configure_widget_target.rb`: Cập nhật `MARKETING_VERSION = '1.1.2'`, `CURRENT_PROJECT_VERSION = '12'`.
  - `ios_app/LANMonitorWidget/Info.plist`: Cập nhật `CFBundleShortVersionString = 1.1.2`, `CFBundleVersion = 12`.
  - `.github/workflows/build_ios.yml`: Cập nhật target release lên `v1.1.2`.
  - `PROJECT_RULES.md`: Khởi tạo bộ quy chuẩn bắt buộc cho dự án và AI Agent.
  - `CHANGELOG.md`: Khởi tạo và ghi nhận lịch sử phiên bản.

---

## [v1.1.1] - 2026-11-16 (Build 11)
- **Mục tiêu thay đổi**: Khắc phục triệt để lỗi Widget không hiển thị trong Thư viện tiện ích (Widget Gallery) trên iOS 17/18 bằng cách đồng bộ 100% `CFBundleShortVersionString` và `CFBundleVersion` vào `Info.plist` của Extension, hỗ trợ cả 2 App Group.
- **Commit SHA**: `3e26be3`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 3e26be3 --no-edit
  ```
- **Chi tiết kỹ thuật**:
  - Sửa script CI dùng Python inject chính xác `CFBundleShortVersionString` (1.1.1) và `CFBundleVersion` (11) vào `LANMonitorWidgetExtension.appex/Info.plist`.
  - Thêm `group.com.lanmonitor.lanMonitor` vào cả Host và Extension entitlements.
  - Loại bỏ `PkgInfo` thừa trong `.appex` để tương thích cấu trúc Gas Manager.

---

## [v1.1.0] - 2026-11-16 (Build 10)
- **Mục tiêu thay đổi**: Biên dịch native target `LANMonitorWidgetExtension` bằng `xcodebuild` với Shared Scheme độc lập, loại bỏ xung đột vòng lặp `Thin Binary` của Flutter.
- **Commit SHA**: `a3a6b0a`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert a3a6b0a --no-edit
  ```
- **Chi tiết kỹ thuật**:
  - Tạo `configure_widget_target.rb` cấu hình App Extension Target và Shared Scheme `.xcscheme`.
  - Tách rời quá trình build `Runner.app` và `LANMonitorWidgetExtension.appex`.

---

## [v1.0.0] - 2026-11-10 (Build 1)
- **Mục tiêu thay đổi**: Khởi tạo hệ thống giám sát phần cứng LAN Monitor gồm Server Daemon (`agent.py`), Desktop GUI (`dashboard.py`) và ứng dụng di động iOS (`ios_app`).
