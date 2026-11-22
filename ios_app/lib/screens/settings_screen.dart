import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/monitor_provider.dart';
import 'config_sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showEditTokenDialog(BuildContext context, MonitorProvider provider) {
    final tokenCtrl = TextEditingController(text: provider.globalToken);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Mã Secret Token Chung'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: tokenCtrl,
            placeholder: 'Nhập mã Token bảo mật',
            padding: const EdgeInsets.all(10),
          ),
        ),
        actions: [
          CupertinoDialogAction(child: const Text('Hủy'), onPressed: () => Navigator.pop(ctx)),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Lưu'),
            onPressed: () {
              provider.setGlobalToken(tokenCtrl.text.trim());
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MonitorProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryText = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        title: Text('Cài đặt & Cấu hình', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: primaryText)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Kết nối & Bảo mật
          Text('BẢO MẬT & KẾT NỐI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: ListTile(
              leading: const Icon(CupertinoIcons.lock_shield, color: Color(0xFF0284C7)),
              title: Text('Mã Secret Token', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
              subtitle: Text(provider.globalToken, style: TextStyle(fontSize: 12, color: secondaryText)),
              trailing: const Icon(CupertinoIcons.pencil, size: 18),
              onTap: () => _showEditTokenDialog(context, provider),
            ),
          ),
          const SizedBox(height: 20),

          // Section 1.5: Đồng bộ Cấu hình dashboard_config.json
          Text('ĐỒNG BỘ CẤU HÌNH (DASHBOARD_CONFIG.JSON)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: ListTile(
              leading: const Icon(CupertinoIcons.arrow_2_circlepath_circle, color: Color(0xFF10B981)),
              title: Text('Đồng bộ file dashboard_config.json', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
              subtitle: Text('Đồng bộ Online qua URL, dán JSON hoặc khôi phục từ Windows.', style: TextStyle(fontSize: 12, color: secondaryText)),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const ConfigSyncScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: Tần suất làm mới
          Text('TẦN SUẤT LÀM MỚI DỮ LIỆU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(CupertinoIcons.arrow_2_circlepath, color: Color(0xFF10B981)),
                  title: Text('Tự động làm mới', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
                  subtitle: Text('Đang cập nhật mỗi ${provider.refreshInterval} giây', style: TextStyle(fontSize: 12, color: secondaryText)),
                  value: provider.isAutoRefresh,
                  activeColor: const Color(0xFF0284C7),
                  onChanged: (val) => provider.setAutoRefresh(val),
                ),
                if (provider.isAutoRefresh) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [1, 2, 5, 10].map((sec) {
                        final isSelected = provider.refreshInterval == sec;
                        return ChoiceChip(
                          label: Text('${sec}s'),
                          selected: isSelected,
                          selectedColor: const Color(0xFF0284C7),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : primaryText,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          onSelected: (_) => provider.setRefreshInterval(sec),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 2.5: Tuỳ chọn hiển thị (Ẩn máy Offline)
          Text('HIỂN THỊ & GIAO DIỆN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: SwitchListTile(
              secondary: Icon(
                provider.hideOffline ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye,
                color: const Color(0xFF0284C7),
              ),
              title: Text('Chỉ hiện máy Online', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryText)),
              subtitle: Text('Tự động ẩn các máy đang mất kết nối (Offline) giống phiên bản Windows.', style: TextStyle(fontSize: 12, color: secondaryText)),
              value: provider.hideOffline,
              activeColor: const Color(0xFF0284C7),
              onChanged: (val) => provider.setHideOffline(val),
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: Quản lý thiết bị
          Text('QUẢN LÝ THIẾT BỊ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: ListTile(
              leading: const Icon(CupertinoIcons.trash, color: Color(0xFFEF4444)),
              title: Text('Xóa sạch 2 thiết bị mẫu (Máy cơ quan)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFFEF4444))),
              subtitle: Text('Xóa triệt để các máy mẫu không kết nối được và chỉ giữ lại máy thật của bạn.', style: TextStyle(fontSize: 12, color: secondaryText)),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: () {
                provider.clearMockHosts();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xóa sạch các thiết bị mẫu!'),
                    backgroundColor: Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Section 4: Hướng dẫn kết nối từ xa
          Text('KẾT NỐI TỪ XA QUA TAILSCALE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.globe, color: Color(0xFF0284C7), size: 20),
                    const SizedBox(width: 8),
                    Text('Giám sát qua 4G/5G hoặc Wi-Fi ngoài', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Cài đặt ứng dụng "Tailscale" trên iPhone từ App Store.\n'
                  '2. Đăng nhập cùng tài khoản Tailscale với máy tính của bạn.\n'
                  '3. Khi thêm máy trên app, nhập địa chỉ IP dạng 100.x.x.x của máy cơ quan.\n'
                  '4. Bạn có thể theo dõi và điều khiển máy tính từ bất cứ đâu!',
                  style: TextStyle(fontSize: 12, color: secondaryText, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Version info
          Center(
            child: Column(
              children: [
                Text('LAN Monitor Dashboard for iOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryText)),
                const SizedBox(height: 2),
                Text('Phiên bản 1.2.7 (Build 24)', style: TextStyle(fontSize: 11, color: secondaryText.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
