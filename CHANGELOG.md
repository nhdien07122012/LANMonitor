# 📋 Nhật ký thay đổi (Changelog) - LAN Monitor

Tài liệu này ghi lại toàn bộ lịch sử phát triển, các phiên bản phát hành, chi tiết kỹ thuật và lệnh rollback khẩn cấp cho từng phiên bản theo đúng quy chuẩn dự án tại `PROJECT_RULES.md`.

---

## [v1.2.4] - 2026-11-16 (Build 21)
- **Mục tiêu thay đổi**:
  1. **Khắc phục triệt để lỗi Widget báo "Không có máy online / Tất cả máy đang tắt" khi cài đặt qua E-Sign / AltStore / Sideload**:
     - Do việc cài đặt ứng dụng qua các công cụ sideload (E-Sign) thường dùng chứng chỉ tự cấp hoặc chia sẻ không có quyền Apple App Group đã đăng ký, hệ thống iOS chặn việc chia sẻ App Group (`UserDefaults(suiteName:)` trả về `nil`).
     - Bổ sung cơ chế **tự hành độc lập (autonomous fallback)** trong Widget: Khi bộ nhớ đệm rỗng hoặc chỉ có các máy cũ, Widget tự động nạp thiết bị mặc định `"Máy tính (Tailscale)"` (`100.66.18.111:8765`) và trực tiếp gửi yêu cầu HTTP đến endpoint `/metrics` thông qua mạng Tailscale của hệ thống.
  2. **Bộ lọc dọn dẹp các máy mẫu cũ (`filterLegacyHosts`)**: Loại bỏ triệt để các máy giả lập cũ (`192.168.1.10`, `100.100.100.100`, `"Máy cơ quan"`) khỏi toàn bộ các tầng cache của Widget để tránh việc widget cố gắng truy vấn các IP này dẫn tới báo Offline sai lệch.
  3. **Hỗ trợ kết nối qua 4G/LTE/Cellular & Tăng Timeout mạng**:
     - Cấu hình `allowsCellularAccess = true` và `waitsForConnectivity = false` cho `URLSessionConfiguration` của Widget.
     - Tăng thời gian chờ (timeout) từ 2.5s lên 5.0s, thích ứng tối ưu với độ trễ bắt tay mạng Tailscale qua dữ liệu di động (LTE).
  4. **Khắc phục lỗi cắt chữ Header Widget (`LAN Mon...`)**:
     - Thêm `.minimumScaleFactor(0.8)` và `.lineLimit(1)` cho tiêu đề "LAN Monitor" trên tất cả các view của Widget (Small, Medium, Empty).
  5. **Cải tiến khởi tạo Flutter MethodChannel trên AppDelegate**:
     - Duyệt scene an toàn (`UIWindowScene`) để đảm bảo kênh `com.lanmonitor/widget` luôn được đăng ký chính xác ngay cả khi `window?.rootViewController` chưa sẵn sàng ở bước `didFinishLaunchingWithOptions`.
- **Phiên bản & Tag**: `v1.2.4` (Build 21)
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert HEAD --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Thêm hàm `getDefaultHosts()` trả về `100.66.18.111`.
    - Thêm hàm `filterLegacyHosts()` loại bỏ các IP mẫu cũ.
    - Cập nhật `getTimeline()` và `getSnapshot()` tự động dự phòng sang `getDefaultHosts()` thay vì kết thúc sớm với danh sách rỗng.
    - Cấu hình `allowsCellularAccess = true` và timeout 5.0s trong `checkHostStatus()`.
    - Thêm `minimumScaleFactor(0.8)` cho tiêu đề để chống cắt chữ `"LAN Mon..."`.
  - `ios_app/patch_app_delegate.py`:
    - Bổ sung `setupChannelIfNeeded` an toàn qua `UIWindowScene` và dynamic `group.\(bundleId)`.
  - `ios_app/App.entitlements` & `ios_app/LANMonitorWidget/LANMonitorWidget.entitlements`:
    - Bổ sung thêm App Group `group.com.lanmonitor`.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Đồng bộ nâng phiên bản lên `v1.2.4` (Build `21`).

---

## [v1.2.3] - 2026-11-16 (Build 20)
- **Mục tiêu thay đổi**:
  1. **Thay đổi thiết bị mặc định sang Tailscale IP `100.66.18.111`**: Thiết lập máy mặc định duy nhất là `"Máy tính (Tailscale)"` với IP `100.66.18.111`, port `8765`.
  2. **Tự động dọn dẹp triệt để các máy ảo cũ (192.168.1.10 & 100.100.100.100)**: Ngay khi ứng dụng khởi động hoặc khôi phục, tự động quét và xóa sạch các mục máy mẫu không thể kết nối, đảm bảo khi cài app đè lên không bị vướng lại máy ảo cũ.
  3. **Cập nhật đồng bộ toàn bộ file cấu hình**: Cập nhật file `dashboard_config.json`, file tài nguyên `ios_app/assets/dashboard_config.json`, và cập nhật trực tiếp dữ liệu GitHub Gist API sang IP mới `100.66.18.111`.
- **Phiên bản & Tag**: `v1.2.3` (Build 20)
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert HEAD --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `dashboard_config.json` & `ios_app/assets/dashboard_config.json`:
    - Thay thế danh sách 2 máy cũ bằng duy nhất 1 máy: `{"name": "Máy tính (Tailscale)", "ip": "100.66.18.111"}`.
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Thêm cơ chế tự động xóa các máy mẫu cũ (`192.168.1.10`, `100.100.100.100`) trong hàm nạp cấu hình `_loadFromPrefs()` và `clearMockHosts()`.
    - Thiết lập máy mặc định là `100.66.18.111`.
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Cập nhật hàm xem trước `createPreviewEntry()` sang `100.66.18.111`.
  - `ios_app/lib/screens/config_sync_screen.dart`:
    - Cập nhật placeholder sang `100.66.18.111`.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Đồng bộ nâng phiên bản lên `v1.2.3` (Build `20`).

---

## [v1.2.2] - 2026-11-16 (Build 19)
- **Mục tiêu thay đổi**:
  1. **Khắc phục lỗi Widget không đồng bộ máy từ app**: Đồng bộ cả 2 khóa `widget_hosts_json` và `hosts_json` qua App Group và `UserDefaults.standard` / `widget_hosts.json`. Xóa bỏ hoàn toàn danh sách máy ảo giả định (dummy hosts) khi chưa kết nối.
  2. **Chỉ hiển thị các máy đang hoạt động (Active Hosts Only)**: Bộ lọc `entry.hosts.filter { $0.isOnline }` loại bỏ toàn bộ các máy đang tắt/ngoại tuyến khỏi Widget.
  3. **Thiết kế lại toàn diện giao diện Widget Small & Medium - Không mất chữ**:
     - *Khi 0 máy online*: Hiển thị thông báo tinh tế "Không có máy online" / "Tất cả máy đang tắt", kèm nút chạm mở app.
     - *Khi 1 máy online (Small Widget)*: Hiển thị thẻ chuyên biệt kích thước lớn: Tên máy cỡ 14pt bold 2 dòng (tự co giãn chữ, không bao giờ bị cắt '...'), địa chỉ IP monospaced riêng biệt 1 dòng, badge CPU, tốc độ mạng tải xuống và thời gian Uptime rõ nét.
     - *Khi 2 máy online trở lên*: Mỗi máy có 2 dòng (dòng 1: Tên + CPU%, dòng 2: IP + tốc độ tải), loại bỏ tình trạng co kéo chiều ngang gây mất chữ.
     - *Medium Widget*: Thẻ máy tính ngang rộng rãi, hiển thị CPU, RAM, Tốc độ tải, hỗ trợ chạm trực tiếp vào từng máy để mở chi tiết thông số.
  4. **Tự động làm mới khi mở lại ứng dụng**: Tích hợp `WidgetsBindingObserver` trong `DashboardScreen` để làm mới danh sách máy và đẩy dữ liệu tức thì sang Widget ngay khi app được mở từ màn hình chính hoặc từ Widget tap.
- **Phiên bản & Tag**: `v1.2.2` (Build 19)
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert HEAD --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Bổ sung gửi đồng thời `hosts_json`, `widget_hosts_json`, `widget_token` trong `_syncHostsToWidget()`.
    - Thêm dự phòng lưu trực tiếp vào `SharedPreferences`.
  - `ios_app/lib/screens/dashboard_screen.dart`:
    - Thêm mixin `WidgetsBindingObserver` để tự động gọi `provider.refreshAll()` khi app chuyển sang trạng thái `resumed`.
  - `ios_app/patch_app_delegate.py`:
    - Lưu thêm bản sao dữ liệu vào `UserDefaults.standard` bên cạnh App Group UserDefaults và file `widget_hosts.json`.
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Cập nhật hàm `loadCachedHosts()` tìm kiếm qua nhiều tầng lưu trữ (`widget_hosts_json`, `hosts_json`, App Groups, UserDefaults standard, JSON container).
    - Xóa bỏ danh sách dummy hosts mặc định ("Máy cơ quan", "Talescale-Máy cơ quan", "SRO130").
    - Thêm cơ chế bảo toàn trạng thái Online từ app trong vòng 3 phút khi Widget chạy nền gặp giới hạn mạng sandbox.
    - Tái cấu trúc `SmallWidgetView` thành 3 chế độ: `emptyView`, `singleHostView`, `multiHostsView` với `minimumScaleFactor(0.8)` đảm bảo không cắt chữ hay xuất hiện `...`.
    - Tái cấu trúc `MediumWidgetView` với bộ lọc chỉ máy đang hoạt động.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Đồng bộ nâng phiên bản lên `v1.2.2` (Build `19`).

---

## [v1.2.1] - 2026-11-16 (Build 18)
- **Mục tiêu thay đổi**: Tạo Gist trực tuyến công khai và tích hợp sẵn URL đồng bộ mặc định cho file `dashboard_config.json` vào ứng dụng, giúp người dùng mở màn hình đồng bộ là có sẵn link tải ngay không cần gõ hay dán thủ công.
- **Commit SHA**: `2c072f7`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 2c072f7 --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/lib/screens/config_sync_screen.dart`:
    - Tự động điền sẵn URL đồng bộ trực tuyến `https://gist.githubusercontent.com/nhdien07122012/f540d4882c4c87e2dc799975faa57a03/raw/dashboard_config.json` khi mở màn hình.
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Đặt URL Gist làm giá trị mặc định cho `_configSyncUrl` khi chưa có cấu hình trước đó.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`, `.github/workflows/build_ios.yml`:
    - Nâng phiên bản đồng bộ lên `v1.2.1` (Build `18`).

---

## [v1.2.0] - 2026-11-16 (Build 17)
- **Mục tiêu thay đổi**:
  1. Chuyển đổi Widget từ theo dõi chi tiết 1 máy thành **Widget Giám sát Trạng thái Toàn bộ Máy tính (Hosts Status Overview)**: hiển thị danh sách các máy, trạng thái Online/Offline, số lượng máy đang chạy; hỗ trợ bấm trực tiếp vào từng máy trên widget để mở app và điều hướng thẳng đến màn hình chi tiết thông số qua deep link (`lanmonitor://host?id=...`).
  2. Bổ sung tính năng **Đồng bộ và Nạp Cấu hình `dashboard_config.json`** chuẩn như phiên bản Windows: hỗ trợ đồng bộ Online qua URL, dán JSON từ bộ nhớ tạm, khôi phục từ file gốc và xuất cấu hình (Export).
- **Commit SHA**: `332a8ba`
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert 332a8ba --no-edit
  ```
- **Chi tiết kỹ thuật các file đã chỉnh sửa**:
  - `ios_app/LANMonitorWidget/LANMonitorWidget.swift` & `ios_app/ios_widget/LANMonitorWidget.swift`:
    - Thay thế mô hình `SimpleEntry` cũ bằng mô hình đa thiết bị `HostWidgetItem` và `SimpleEntry(hosts: [HostWidgetItem], onlineCount: Int, totalCount: Int)`.
    - `SmallWidgetView` (.systemSmall): Hiển thị danh sách 3 máy với chấm trạng thái xanh/đỏ, IP, CPU% và badge tổng quan `● online/total`, tích hợp `.widgetURL` mở app.
    - `MediumWidgetView` (.systemMedium): Hiển thị header badge số máy đang chạy, danh sách thẻ máy tính tích hợp `Link(destination: URL(string: "lanmonitor://host?id=..."))` cho phép chạm vào từng máy để mở trực tiếp thông số máy đó.
    - Duy trì cơ chế kiểm tra mạng trực tiếp độc lập (`URLSession`) trong `getTimeline()`.
  - `ios_app/patch_app_delegate.py`:
    - Bổ sung `application(_:open:options:)` xử lý deep link URL scheme `lanmonitor://`, lưu `pending_open_url` và gửi event `openHostUrl` vào Flutter.
    - Bổ sung xử lý MethodChannel `updateWidgetHosts` và `getPendingOpenUrl`.
  - `.github/workflows/build_ios.yml`:
    - Đăng ký `CFBundleURLTypes` với URL scheme `lanmonitor` trong `Runner/Info.plist`.
  - `ios_app/lib/screens/config_sync_screen.dart`:
    - Tạo mới màn hình Quản lý & Đồng bộ cấu hình `dashboard_config.json`: Đồng bộ online qua URL, dán JSON từ Clipboard, khôi phục từ file gốc, xuất file JSON.
  - `ios_app/lib/providers/monitor_provider.dart`:
    - Bổ sung hàm `importConfigJson()`, `syncConfigFromUrl()`, `loadBundledConfig()`, `exportConfigJson()`, `_syncHostsToWidget()`.
    - Lắng nghe deep link `openHostUrl` và điều hướng người dùng tới máy được chọn.
  - `ios_app/lib/screens/dashboard_screen.dart` & `ios_app/lib/screens/settings_screen.dart`:
    - Bổ sung icon và menu truy cập nhanh màn hình Đồng bộ `dashboard_config.json`.
    - Xử lý mở `HostDetailScreen` tự động khi nhận tín hiệu từ Widget tap.
  - `ios_app/assets/dashboard_config.json`:
    - Sao chép tệp cấu hình mẫu từ thư mục gốc vào `assets/` của ứng dụng.
  - `ios_app/pubspec.yaml`, `ios_app/configure_widget_target.rb`, `ios_app/LANMonitorWidget/Info.plist`, `ios_app/ios_widget/Info.plist`:
    - Đồng bộ nâng phiên bản lên `v1.2.0` (Build `17`).

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
