import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host_model.dart';
import '../models/metrics_model.dart';
import '../providers/monitor_provider.dart';
import 'ring_gauge.dart';
import 'quick_control_sheet.dart';
import '../screens/host_detail_screen.dart';

class HostCard extends StatelessWidget {
  final HostModel host;

  const HostCard({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = host.isOnline;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryText = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final statusColor = isOnline == true
        ? const Color(0xFF10B981) // Emerald Online
        : (isOnline == false ? const Color(0xFFEF4444) : const Color(0xFF64748B));

    final cardContent = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => HostDetailScreen(host: host)),
            );
          },
          onLongPress: () => QuickControlSheet.show(context, host),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header: Dot, Name, IP Badge, Control Button
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        host.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: primaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        host.ip,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(CupertinoIcons.ellipsis_circle, size: 20),
                      color: secondaryText,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => QuickControlSheet.show(context, host),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Metrics Body (Twin Rings, Disk bar, Network)
                if (isOnline == true && host.metrics != null) ...[
                  Row(
                    children: [
                      // Twin Rings: CPU & RAM
                      RingGaugeWidget(
                        value: host.metrics!.cpuPercent,
                        title: 'CPU',
                        size: 42,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      RingGaugeWidget(
                        value: host.metrics!.ramPercent,
                        title: 'RAM',
                        size: 42,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 14),

                      // Disk & Net info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Disk progress bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Ổ đĩa (Disk)', style: TextStyle(fontSize: 11, color: secondaryText)),
                                Text(
                                  '${host.metrics!.diskPercent.toStringAsFixed(0)}%',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryText),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: host.metrics!.diskPercent / 100.0,
                                minHeight: 4,
                                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                color: host.metrics!.diskPercent >= 85
                                    ? Colors.redAccent
                                    : (host.metrics!.diskPercent >= 70 ? Colors.amber : const Color(0xFF0284C7)),
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Network speed & Uptime
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(CupertinoIcons.arrow_down, size: 10, color: Color(0xFF10B981)),
                                    Text(
                                      MetricsModel.formatSpeed(host.metrics!.downloadBps),
                                      style: TextStyle(fontSize: 10, color: secondaryText),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(CupertinoIcons.arrow_up, size: 10, color: Color(0xFF38BDF8)),
                                    Text(
                                      MetricsModel.formatSpeed(host.metrics!.uploadBps),
                                      style: TextStyle(fontSize: 10, color: secondaryText),
                                    ),
                                  ],
                                ),
                                Text(
                                  host.metrics!.formattedUptime,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: secondaryText),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (isOnline == false) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF450A0A).withOpacity(0.4) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 16, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            host.errorMessage ?? 'Không thể kết nối đến máy (Offline)',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: CupertinoActivityIndicator(radius: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: Key(host.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Xóa thiết bị'),
            content: Text('Bạn có chắc chắn muốn xóa "${host.name}" khỏi danh sách?'),
            actions: [
              CupertinoDialogAction(
                child: const Text('Hủy'),
                onPressed: () => Navigator.pop(ctx, false),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        Provider.of<MonitorProvider>(context, listen: false).deleteHost(host.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa "${host.name}"'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(CupertinoIcons.trash, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text(
              'Xóa',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
      child: cardContent,
    );
  }
}
