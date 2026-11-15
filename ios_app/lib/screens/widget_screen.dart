import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host_model.dart';
import '../providers/monitor_provider.dart';
import '../widgets/ring_gauge.dart';

class WidgetScreen extends StatefulWidget {
  const WidgetScreen({super.key});

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  String? _selectedHostId;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MonitorProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hosts = provider.hosts;
    if (hosts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chế độ Widget')),
        body: const Center(child: Text('Chưa có máy tính nào trong danh sách')),
      );
    }

    // Default select first online host or first host
    final currentHost = hosts.firstWhere(
      (h) => h.id == _selectedHostId,
      orElse: () => hosts.firstWhere((h) => h.isOnline == true, orElse: () => hosts.first),
    );

    final metrics = currentHost.metrics;
    final isOnline = currentHost.isOnline == true;

    final bgColor = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryText = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B0F19) : Colors.white,
        elevation: 0,
        title: const Text(
          'Widget & StandBy Monitor',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          // Host Selector dropdown
          if (hosts.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.arrow_2_squarepath, size: 20),
              tooltip: 'Đổi máy',
              onSelected: (id) => setState(() => _selectedHostId = id),
              itemBuilder: (ctx) => hosts.map((h) {
                return PopupMenuItem(
                  value: h.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: h.isOnline == true ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(h.name, style: TextStyle(fontWeight: h.id == currentHost.id ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Dynamic Island Minimal Capsule (iPhone Dynamic Island Style)
            Text(
              '1. Dynamic Island Capsule (Bong bóng nổi)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: secondaryText),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black, // Pure OLED black capsule
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      boxShadow: isOnline
                          ? [
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.8),
                                blurRadius: 6,
                              )
                            ]
                          : [],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentHost.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isOnline ? currentHost.ip : 'Mất kết nối',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOnline && metrics != null) ...[
                    RingGaugeWidget(
                      value: metrics.cpuPercent,
                      title: 'CPU',
                      size: 38,
                      isDark: true,
                    ),
                    const SizedBox(width: 10),
                    RingGaugeWidget(
                      value: metrics.ramPercent,
                      title: 'RAM',
                      size: 38,
                      isDark: true,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. iOS Home Widget (Square 2x2 Preview)
            Text(
              '2. Widget Home Screen (Dạng thẻ vuông iOS)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: secondaryText),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 168,
                height: 168,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header: Dot + Name
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            currentHost.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primaryText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Twin Rings Center
                    if (isOnline && metrics != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          RingGaugeWidget(
                            value: metrics.cpuPercent,
                            title: 'CPU',
                            size: 48,
                            isDark: isDark,
                          ),
                          RingGaugeWidget(
                            value: metrics.ramPercent,
                            title: 'RAM',
                            size: 48,
                            isDark: isDark,
                          ),
                        ],
                      )
                    else
                      Center(
                        child: Text(
                          'Offline',
                          style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                      ),

                    // Disk Mini bar
                    if (isOnline && metrics != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ổ đĩa', style: TextStyle(fontSize: 9, color: secondaryText)),
                              Text('${metrics.diskPercent.toStringAsFixed(0)}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: primaryText)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: (metrics.diskPercent / 100).clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 3. Apple StandBy Mode Card (Dành cho sạc ngang bàn làm việc)
            Text(
              '3. Chế độ StandBy Monitor (Màn hình để bàn)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: secondaryText),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(CupertinoIcons.desktopcomputer, size: 18, color: Color(0xFF0284C7)),
                          const SizedBox(width: 8),
                          Text(
                            currentHost.name,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryText),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFFEF4444).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isOnline ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isOnline && metrics != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            RingGaugeWidget(value: metrics.cpuPercent, title: 'CPU', size: 68, isDark: isDark),
                            const SizedBox(height: 6),
                            Text('CPU Usage', style: TextStyle(fontSize: 11, color: secondaryText)),
                          ],
                        ),
                        Column(
                          children: [
                            RingGaugeWidget(value: metrics.ramPercent, title: 'RAM', size: 68, isDark: isDark),
                            const SizedBox(height: 6),
                            Text('RAM Usage', style: TextStyle(fontSize: 11, color: secondaryText)),
                          ],
                        ),
                        Column(
                          children: [
                            RingGaugeWidget(value: metrics.diskPercent, title: 'DISK', size: 68, isDark: isDark),
                            const SizedBox(height: 6),
                            Text('Ổ đĩa C:', style: TextStyle(fontSize: 11, color: secondaryText)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(CupertinoIcons.arrow_down_circle_fill, size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            Text(metrics.formattedDownloadRate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryText)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(CupertinoIcons.arrow_up_circle_fill, size: 16, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(metrics.formattedUploadRate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryText)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(CupertinoIcons.time, size: 16, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Text(metrics.formattedUptime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryText)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
