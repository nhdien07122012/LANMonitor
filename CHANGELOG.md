# 📋 Nhật ký thay đổi (Changelog) - LAN Monitor

Tài liệu này ghi lại toàn bộ lịch sử phát triển, các phiên bản phát hành, chi tiết kỹ thuật và lệnh rollback khẩn cấp cho từng phiên bản theo đúng quy chuẩn dự án tại `PROJECT_RULES.md`.

---

## [v1.1.2] - 2026-11-16 (Build 12)
- **Mục tiêu thay đổi**: Bổ sung hỗ trợ đầy đủ giao diện Light Mode (chế độ sáng) và Dark Mode (chế độ tối) tự động cho iOS Home Screen Widget, đồng bộ màu sắc sắc nét theo đúng palette giao diện của ứng dụng Flutter; tích hợp bộ quy chuẩn `PROJECT_RULES.md`.
- **Commit SHA**: *(Commit hiện tại)*
- **Lệnh hoàn tác mẫu (Rollback)**:
  ```bash
  git revert HEAD --no-edit
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
