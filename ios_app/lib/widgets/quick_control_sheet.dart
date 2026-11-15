import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/host_model.dart';
import '../providers/monitor_provider.dart';

class QuickControlSheet extends StatelessWidget {
  final HostModel host;

  const QuickControlSheet({super.key, required this.host});

  static void show(BuildContext context, HostModel host) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QuickControlSheet(host: host),
    );
  }

  Future<void> _openRdp(BuildContext context) async {
    final rdpUrl = Uri.parse('rdp://full-address=s:${host.ip}:3389');
    try {
      if (await canLaunchUrl(rdpUrl)) {
        await launchUrl(rdpUrl);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vui lòng cài đặt ứng dụng "Microsoft Remote Desktop" từ App Store để mở RDP.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi mở RDP: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _triggerControl(BuildContext context, String action, {String? appPath, String? url}) async {
    Navigator.pop(context);
    final provider = Provider.of<MonitorProvider>(context, listen: false);
    final msg = await provider.sendControl(host, action, appPath: appPath, url: url);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: msg.startsWith('Lỗi') ? Colors.red : const Color(0xFF0284C7),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MonitorProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sheetBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryText = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final itemBg = isDark ? const Color(0xFF334155).withOpacity(0.5) : const Color(0xFFF1F5F9);

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag indicator
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: secondaryText.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Icon(CupertinoIcons.desktopcomputer, color: const Color(0xFF0284C7), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                    ),
                    Text(
                      '${host.ip}:${host.port}',
                      style: TextStyle(fontSize: 12, color: secondaryText),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.xmark_circle_fill),
                color: secondaryText,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action 1: Kết nối RDP
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.desktopcomputer, size: 18),
            label: const Text('Kết nối RDP (Remote Desktop)', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _openRdp(context),
          ),
          const SizedBox(height: 14),

          // Action Grid: Tắt máy, Khởi động, Sleep
          Text('Điều khiển nguồn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryText)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  context,
                  icon: CupertinoIcons.power,
                  label: 'Tắt máy',
                  color: const Color(0xFFEF4444),
                  bgColor: itemBg,
                  onTap: () => _confirmAction(context, 'Tắt máy', () => _triggerControl(context, 'shutdown')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  context,
                  icon: CupertinoIcons.arrow_clockwise,
                  label: 'Khởi động',
                  color: const Color(0xFFF59E0B),
                  bgColor: itemBg,
                  onTap: () => _confirmAction(context, 'Khởi động lại', () => _triggerControl(context, 'reboot')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  context,
                  icon: CupertinoIcons.moon_fill,
                  label: 'Sleep',
                  color: const Color(0xFF8B5CF6),
                  bgColor: itemBg,
                  onTap: () => _triggerControl(context, 'sleep'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Quick Apps Menu
          if (provider.customApps.isNotEmpty) ...[
            Text('Chạy ứng dụng từ xa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryText)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.customApps.entries.map((e) {
                return ActionChip(
                  avatar: const Icon(CupertinoIcons.play_arrow_solid, size: 14, color: Color(0xFF0284C7)),
                  label: Text(e.key),
                  backgroundColor: itemBg,
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: primaryText),
                  onPressed: () => _triggerControl(context, 'run_app', appPath: e.value),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Quick Links Menu
          if (provider.customLinks.isNotEmpty) ...[
            Text('Mở đường link (URL)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryText)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.customLinks.entries.map((e) {
                return ActionChip(
                  avatar: const Icon(CupertinoIcons.globe, size: 14, color: Color(0xFF10B981)),
                  label: Text(e.key),
                  backgroundColor: itemBg,
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: primaryText),
                  onPressed: () => _triggerControl(context, 'open_url', url: e.value),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  void _confirmAction(BuildContext context, String actionTitle, VoidCallback onConfirm) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Xác nhận $actionTitle'),
        content: Text('Bạn có chắc muốn thực hiện $actionTitle cho "${host.name}" không?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Hủy'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Thực hiện'),
          ),
        ],
      ),
    );
  }
}
