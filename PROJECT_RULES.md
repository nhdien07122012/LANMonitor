# 🤖 Project Standard Rules & AI Agent Instructions

Tài liệu này là bộ quy chuẩn kỷ luật bắt buộc dành cho mọi AI Agent và Developer khi làm việc trên dự án LAN Monitor. Mọi hành động chỉnh sửa mã nguồn, cấu trúc dữ liệu hoặc giao diện đều phải tuân thủ nghiêm ngặt các điều khoản dưới đây:

---

## 🛡️ 1. QUY TẮC BẢO TOÀN PHẠM VI & XÁC NHẬN KHI CÓ ẢNH HƯỞNG LIÊN ĐỚI (Scope Preservation & Impact Confirmation - BẮT BUỘC SỐ 1)

> [!CAUTION]
> **ĐIỀU KHOẢN BẤT DI BẤT DỊCH:**
> 1. **Giữ nguyên 100% các chức năng không được đề cập**:
>    - Mỗi khi người dùng yêu cầu thêm mới, sửa lỗi hoặc thay đổi một tính năng/giao diện cụ thể: AI **CHỈ ĐƯỢC PHÉP** can thiệp đúng vào phạm vi được yêu cầu.
>    - Mọi tính năng, màn hình, cấu trúc dữ liệu, luồng tính toán khác KHÔNG được đề cập trong yêu cầu **BẮT BUỘC PHẢI GIỮ NGUYÊN HOÀN TOÀN**. Tuyệt đối không tự ý tái cấu trúc (refactor), xóa bỏ, đổi tên hàm hay thay đổi cách hoạt động vốn có của các phần khác (Server Agent `agent.py`, Desktop GUI `dashboard.py`, Flutter screens, WidgetKit).
> 2. **Bắt buộc dừng lại hỏi ý kiến trước khi làm nếu có tác động liên đới**:
>    - Nếu việc thực hiện yêu cầu bắt buộc phải sửa đổi, can thiệp hoặc có nguy cơ làm ảnh hưởng/lỗi bất kỳ chức năng liên quan nào khác: AI **PHẢI DỪNG LẠI NGAY LẬP TỨC, GIẢI THÍCH RÕ NGUY CƠ VÀ XIN Ý KIẾN NGƯỜI DÙNG** trước khi viết code.
>    - Chỉ được phép tiến hành khi người dùng đã xem xét và đồng ý với phương án tác động liên đới đó.
> 3. **Kiểm tra hồi quy (No Regression)**:
>    - Tuyệt đối không xóa bỏ hay sửa đổi các hàm tiện ích dùng chung (format tốc độ mạng, định dạng uptime, theme, navigation...) mà các trang hoặc sự kiện khác đang sử dụng.

---

## 📌 2. QUY TẮC NHẬT KÝ THAY ĐỔI (Changelog & Rollback Rule)
- Mọi lần thay đổi (dù lớn hay nhỏ), **BẮT BUỘC** phải cập nhật một mục phiên bản mới lên đầu file `CHANGELOG.md` trước khi commit.
- Mỗi bản ghi trong `CHANGELOG.md` phải có đầy đủ:
  - Số hiệu Phiên bản (Version) & Mã bản dựng (Build Number).
  - Commit SHA.
  - Mục tiêu thay đổi tóm tắt.
  - Chi tiết kỹ thuật các file đã chỉnh sửa.
  - **Lệnh hoàn tác mẫu (`git revert <commit_sha> --no-edit`)** để người dùng có thể rollback lập tức khi cần.

---

## 🏷️ 3. QUY TẮC PHIÊN BẢN GIAO DIỆN (UI Versioning Rule)
- **Khi có thay đổi lớn** (thêm tính năng mới, thay đổi luồng nghiệp vụ quan trọng hoặc cập nhật layout lớn): Tăng version hiển thị trên UI (ví dụ trong màn hình Settings / About) lên 1 chấm nhỏ (vd: `v1.1` ➔ `v1.2`...).
- **Khi là bản vá lỗi nhỏ / UI hotfix**: Giữ nguyên version tag trên UI, chỉ tăng số hiệu Build version ở file cấu hình nền tảng (`pubspec.yaml`, `configure_widget_target.rb`, `Info.plist`) và ghi chú trong `CHANGELOG.md`.

---

## 🔄 4. QUY TẮC ĐỒNG BỘ ĐA NỀN TẢNG (Platform Sync & Build Rules)
*(Áp dụng cho dự án Python Server + Desktop GUI + Flutter iOS App + WidgetKit Native)*:
1. **Đồng bộ mã nguồn Flutter sang Native Extension**:
   - Khi chỉnh sửa dữ liệu chia sẻ giữa App và Widget, đồng bộ App Group (`group.com.lanmonitor.lanMonitor` & `group.com.lanmonitor.app`), khóa `UserDefaults` và các model hiển thị.
2. **Tự động tăng Build Number**:
   - Khi hoàn tất tính năng hoặc sửa lỗi, tăng số `Build Version` trong các file cấu hình tương ứng (`version: x.y.z+BUILD` trong `pubspec.yaml`, `MARKETING_VERSION` & `CURRENT_PROJECT_VERSION` trong `configure_widget_target.rb` và `Info.plist`).
3. **An toàn môi trường thực thi (PowerShell / Terminal)**:
   - Khi chạy các script phức tạp hoặc có chuỗi ký tự đặc biệt trên terminal Windows/PowerShell, ưu tiên tạo script tạm thời (`.py`), thực thi rồi xóa bỏ để tránh lỗi cú pháp escape chuỗi và toán tử bash.

---

## 🚀 5. CHECKLIST BẮT BUỘC TRƯỚC KHI BÁO CÁO HOÀN THÀNH
Trước khi thông báo hoàn tất nhiệm vụ cho người dùng, AI phải tự kiểm tra:
- [ ] **Bảo toàn phạm vi**: Tất cả chức năng ngoài yêu cầu đều nguyên vẹn 100%, không bị ảnh hưởng ngoài ý muốn.
- [ ] Nếu có ảnh hưởng liên đới: Đã hỏi ý kiến và được người dùng đồng ý trước khi can thiệp.
- [ ] Đã kiểm tra cú pháp, không gây crash ứng dụng.
- [ ] Đã đồng bộ cấu hình giữa Flutter và iOS Native Extension.
- [ ] Đã tăng Build Number ở các file cấu hình nền tảng.
- [ ] Đã ghi đầy đủ nhật ký kỹ thuật vào `CHANGELOG.md`.
- [ ] Đã commit và push mã nguồn sạch sẽ lên Git remote.
- [ ] Đã xác minh GitHub Actions build IPA thành công và cung cấp link direct download.
