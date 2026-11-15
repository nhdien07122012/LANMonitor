import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/host_model.dart';
import '../models/metrics_model.dart';
import '../providers/monitor_provider.dart';
import '../widgets/ring_gauge.dart';

class HostDetailScreen extends StatelessWidget {
  final HostModel host;

  const HostDetailScreen({super.key, required this.host});

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<MonitorProvider>(context);

    // Get latest host instance from provider
    final currentHost = provider.hosts.firstWhere((h) => h.id == host.id, orElse: () => host);
    final metrics = currentHost.metrics;
    final isOnline = currentHost.isOnline == true;

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
        title: Text(
          currentHost.name,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: primaryText),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent, size: 20),
            tooltip: 'Xóa máy này',
            onPressed: () {
              showCupertinoDialog(
                context: context,
                builder: (ctx) => CupertinoAlertDialog(
                  title: const Text('Xác nhận xóa'),
                  content: Text('Bạn có chắc muốn xóa "${currentHost.name}" khỏi danh sách?'),
                  actions: [
                    CupertinoDialogAction(child: const Text('Hủy'), onPressed: () => Navigator.pop(ctx)),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      child: const Text('Xóa'),
                      onPressed: () {
                        provider.deleteHost(currentHost.id);
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Connection Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isOnline ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                    const Spacer(),
                    if (metrics != null)
                      Text(
                        'Uptime: ${metrics.formattedUptime}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondaryText),
                      ),
                  ],
                ),
                const Divider(height: 16),
                _buildInfoRow('Địa chỉ IP LAN', currentHost.ip, primaryText, secondaryText),
                if (metrics != null && metrics.tailscaleIp.isNotEmpty)
                  _buildInfoRow('Tailscale IP', metrics.tailscaleIp, const Color(0xFF0284C7), secondaryText),
                _buildInfoRow('Cổng kết nối', currentHost.port.toString(), primaryText, secondaryText),
                if (metrics != null && metrics.hostname.isNotEmpty)
                  _buildInfoRow('Tên máy tính', metrics.hostname, primaryText, secondaryText),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Hardware Metrics (CPU & RAM Giant Rings)
          if (metrics != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tài nguyên hệ thống', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryText)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          RingGaugeWidget(value: metrics.cpuPercent, title: 'CPU', size: 68, isDark: isDark),
                          const SizedBox(height: 8),
                          Text('CPU (${metrics.cpuCount} Cores)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText)),
                        ],
                      ),
                      Column(
                        children: [
                          RingGaugeWidget(value: metrics.ramPercent, title: 'RAM', size: 68, isDark: isDark),
                          const SizedBox(height: 8),
                          Text(
                            'RAM (${metrics.ramUsedGb}/${metrics.ramTotalGb} GB)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Disk Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ổ đĩa chính (C:)', style: TextStyle(fontSize: 12, color: secondaryText)),
                      Text(
                        '${metrics.diskPercent.toStringAsFixed(1)}% (Trống ${metrics.diskFreeGb} GB)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: metrics.diskPercent / 100.0,
                      minHeight: 6,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      color: metrics.diskPercent >= 85 ? Colors.redAccent : const Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Network Speed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(CupertinoIcons.arrow_down_circle_fill, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 6),
                          Text('Tải xuống: ', style: TextStyle(fontSize: 12, color: secondaryText)),
                          Text(MetricsModel.formatSpeed(metrics.downloadBps), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText)),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(CupertinoIcons.arrow_up_circle_fill, color: Color(0xFF38BDF8), size: 16),
                          const SizedBox(width: 6),
                          Text('Tải lên: ', style: TextStyle(fontSize: 12, color: secondaryText)),
                          Text(MetricsModel.formatSpeed(metrics.uploadBps), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText)),
                        ],
                      ),
                    ],
                  ),

                  // GPU info (if available)
                  if (metrics.gpus.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text('Card đồ họa (GPU)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText)),
                    const SizedBox(height: 8),
                    ...metrics.gpus.map((gpu) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(gpu.name, style: TextStyle(fontSize: 12, color: secondaryText), overflow: TextOverflow.ellipsis),
                              ),
                              Text(
                                '${gpu.load.toStringAsFixed(0)}% • ${gpu.temperature.toStringAsFixed(0)}°C',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3. Remote Control Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Thao tác điều khiển từ xa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryText)),
                const SizedBox(height: 14),

                // RDP
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(CupertinoIcons.desktopcomputer, size: 18),
                  label: const Text('Mở Remote Desktop (RDP)', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () => _openRdp(context),
                ),
                const SizedBox(height: 10),

                // Power actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(CupertinoIcons.power, size: 16),
                        label: const Text('Tắt máy', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        onPressed: () => _confirmAction(context, 'Tắt máy', () => _triggerControl(context, 'shutdown')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                        label: const Text('Khởi động', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        onPressed: () => _confirmAction(context, 'Khởi động lại', () => _triggerControl(context, 'reboot')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF8B5CF6),
                          side: const BorderSide(color: Color(0xFF8B5CF6)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(CupertinoIcons.moon_fill, size: 16),
                        label: const Text('Sleep', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        onPressed: () => _triggerControl(context, 'sleep'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valColor)),
        ],
      ),
    );
  }
}
