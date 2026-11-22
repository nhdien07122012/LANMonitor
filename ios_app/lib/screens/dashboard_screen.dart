import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/monitor_provider.dart';
import '../widgets/host_card.dart';
import 'settings_screen.dart';
import 'config_sync_screen.dart';
import 'host_detail_screen.dart';
import '../models/host_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Khi app mở lại từ màn hình nền
      Provider.of<MonitorProvider>(context, listen: false).refreshAll();
    }
  }

  void _showAddHostDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '8765');
    final tokenCtrl = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Thêm Máy Tính Mới'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: nameCtrl,
                placeholder: 'Tên máy (VD: Máy cơ quan)',
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: ipCtrl,
                placeholder: 'Địa chỉ IP (LAN hoặc Tailscale)',
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: portCtrl,
                placeholder: 'Cổng Port (Mặc định: 8765)',
                keyboardType: TextInputType.number,
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: tokenCtrl,
                placeholder: 'Secret Token (Bỏ trống = dùng Token chung)',
                padding: const EdgeInsets.all(10),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Hủy'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Thêm'),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final ip = ipCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 8765;
              final token = tokenCtrl.text.trim();

              if (ip.isNotEmpty) {
                final host = HostModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name.isNotEmpty ? name : 'PC ($ip)',
                  ip: ip,
                  port: port,
                  token: token.isNotEmpty ? token : null,
                );
                Provider.of<MonitorProvider>(context, listen: false).addHost(host);
                Navigator.pop(ctx);
              }
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
    final primaryText = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        titleSpacing: 10,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.desktopcomputer, size: 20, color: Color(0xFF0284C7)),
            const SizedBox(width: 6),
            Text(
              'LAN Monitor',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: primaryText,
              ),
            ),
          ],
        ),
        actions: [
          // Thống kê nhanh Online/Offline (Chạm để bật/tắt lọc chỉ hiện máy Online)
          Center(
            child: GestureDetector(
              onTap: () {
                provider.toggleHideOffline();
                HapticFeedback.lightImpact();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: provider.hideOffline
                      ? const Color(0xFF0284C7).withOpacity(0.2)
                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: provider.hideOffline ? const Color(0xFF0284C7) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${provider.onlineCount}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryText)),
                    const SizedBox(width: 6),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(
                      '${provider.offlineCount}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: provider.hideOffline ? secondaryText.withOpacity(0.5) : primaryText,
                        decoration: provider.hideOffline ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Nút bật/tắt Chỉ hiện máy Online (Eye toggle giống Windows)
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: Icon(
              provider.hideOffline ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye,
              size: 20,
            ),
            color: provider.hideOffline ? const Color(0xFF38BDF8) : secondaryText,
            tooltip: provider.hideOffline ? 'Đang ẩn máy Offline (Chạm để hiện tất cả)' : 'Chỉ hiện máy Online (Ẩn máy Offline)',
            onPressed: () {
              provider.toggleHideOffline();
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(provider.hideOffline ? 'Đã ẩn các máy ngoại tuyến (Offline)' : 'Đang hiện tất cả máy tính'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0284C7),
                ),
              );
            },
          ),
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(CupertinoIcons.arrow_2_circlepath_circle, size: 20),
            color: const Color(0xFF0284C7),
            tooltip: 'Đồng bộ cấu hình JSON',
            onPressed: () {
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const ConfigSyncScreen()),
              );
            },
          ),
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(CupertinoIcons.plus_circle, size: 21),
            color: const Color(0xFF0284C7),
            tooltip: 'Thêm máy tính',
            onPressed: () => _showAddHostDialog(context),
          ),
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(CupertinoIcons.gear, size: 20),
            color: secondaryText,
            tooltip: 'Cài đặt',
            onPressed: () {
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.refreshAll(),
        color: const Color(0xFF0284C7),
        child: provider.hosts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                  Center(
                    child: Column(
                      children: [
                        Icon(CupertinoIcons.desktopcomputer, size: 54, color: secondaryText.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có máy tính nào',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primaryText),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nhấn "+" để thêm máy hoặc nút đồng bộ JSON phía trên.',
                          style: TextStyle(fontSize: 13, color: secondaryText),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(CupertinoIcons.arrow_2_circlepath_circle, size: 16),
                          label: const Text('Đồng bộ dashboard_config.json'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(builder: (_) => const ConfigSyncScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : (provider.displayedHosts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                      Center(
                        child: Column(
                          children: [
                            Icon(CupertinoIcons.eye_slash, size: 54, color: secondaryText.withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'Tất cả máy tính đang ngoại tuyến',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primaryText),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Đang bật chế độ "Chỉ hiện máy Online" nên ${provider.hosts.length} máy ngoại tuyến đã được ẩn.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: secondaryText),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(CupertinoIcons.eye, size: 16),
                              label: const Text('Hiện tất cả máy tính'),
                              onPressed: () {
                                provider.setHideOffline(false);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: provider.displayedHosts.length + (provider.hideOffline && provider.offlineCount > 0 ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i < provider.displayedHosts.length) {
                        return HostCard(host: provider.displayedHosts[i]);
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: secondaryText,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            icon: const Icon(CupertinoIcons.eye, size: 14),
                            label: Text(
                              'Đang ẩn ${provider.offlineCount} máy Offline • Chạm để hiện',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            onPressed: () => provider.setHideOffline(false),
                          ),
                        ),
                      );
                    },
                  )),
      ),
    );
  }
}
