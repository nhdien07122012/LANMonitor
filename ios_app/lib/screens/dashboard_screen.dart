import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/monitor_provider.dart';
import '../widgets/host_card.dart';
import 'settings_screen.dart';
import '../models/host_model.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
        title: Row(
          children: [
            const Icon(CupertinoIcons.desktopcomputer, size: 22, color: Color(0xFF0284C7)),
            const SizedBox(width: 8),
            Text(
              'LAN Monitor',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: primaryText,
              ),
            ),
          ],
        ),
        actions: [
          // Thống kê nhanh Online/Offline
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
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
                  Text('${provider.offlineCount}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryText)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.plus_circle, size: 22),
            color: const Color(0xFF0284C7),
            tooltip: 'Thêm máy tính',
            onPressed: () => _showAddHostDialog(context),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.gear, size: 22),
            color: secondaryText,
            tooltip: 'Cài đặt',
            onPressed: () {
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.refreshAll(),
        color: const Color(0xFF0284C7),
        child: provider.hosts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
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
                          'Nhấn nút "+" ở góc trên để thêm máy tính giám sát.',
                          style: TextStyle(fontSize: 13, color: secondaryText),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: provider.hosts.length,
                itemBuilder: (ctx, i) {
                  return HostCard(host: provider.hosts[i]);
                },
              ),
      ),
    );
  }
}
