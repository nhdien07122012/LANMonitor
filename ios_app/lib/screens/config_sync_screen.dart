import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/monitor_provider.dart';

class ConfigSyncScreen extends StatefulWidget {
  const ConfigSyncScreen({super.key});

  @override
  State<ConfigSyncScreen> createState() => _ConfigSyncScreenState();
}

class _ConfigSyncScreenState extends State<ConfigSyncScreen> {
  final _urlCtrl = TextEditingController();
  final _jsonCtrl = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<MonitorProvider>(context, listen: false);
    if (provider.configSyncUrl != null && provider.configSyncUrl!.isNotEmpty) {
      _urlCtrl.text = provider.configSyncUrl!;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool isSuccess = true}) {
    setState(() {
      _statusMessage = msg;
      _isSuccess = isSuccess;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSyncUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showMessage('Vui lòng nhập đường dẫn URL của file dashboard_config.json.', isSuccess: false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<MonitorProvider>(context, listen: false);
      final result = await provider.syncConfigFromUrl(url);
      _showMessage(
        'Đồng bộ online thành công! Đã cập nhật ${result['hosts']} máy, ${result['apps']} ứng dụng, ${result['links']} liên kết.',
      );
    } catch (e) {
      _showMessage('Lỗi đồng bộ: ${e.toString().replaceAll('Exception: ', '')}', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleImportJson() async {
    final raw = _jsonCtrl.text.trim();
    if (raw.isEmpty) {
      _showMessage('Vui lòng dán nội dung file JSON vào ô bên dưới.', isSuccess: false);
      return;
    }

    try {
      final data = json.decode(raw);
      if (data is! Map<String, dynamic>) {
        throw Exception('Dữ liệu JSON không đúng định dạng đối tượng {}.');
      }

      final provider = Provider.of<MonitorProvider>(context, listen: false);
      final result = await provider.importConfigJson(data);
      _showMessage(
        'Đã nạp cấu hình thành công! Đã thêm ${result['hosts']} máy, ${result['apps']} ứng dụng, ${result['links']} liên kết.',
      );
    } catch (e) {
      _showMessage('Lỗi cú pháp JSON: ${e.toString().replaceAll('Exception: ', '')}', isSuccess: false);
    }
  }

  Future<void> _handlePasteClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _jsonCtrl.text = data.text!;
      });
      _showMessage('Đã dán nội dung từ bộ nhớ tạm.');
    } else {
      _showMessage('Bộ nhớ tạm không có nội dung văn bản.', isSuccess: false);
    }
  }

  Future<void> _handlePasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlCtrl.text = data.text!.trim();
      });
      _showMessage('Đã dán URL từ bộ nhớ tạm.');
    }
  }

  Future<void> _handleLoadBundled() async {
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<MonitorProvider>(context, listen: false);
      final result = await provider.loadBundledConfig();
      _showMessage(
        'Đã khôi phục cấu hình gốc dashboard_config.json: ${result['hosts']} máy, ${result['apps']} ứng dụng!',
      );
    } catch (e) {
      _showMessage('Lỗi nạp cấu hình gốc: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showExportDialog() {
    final provider = Provider.of<MonitorProvider>(context, listen: false);
    final jsonStr = provider.exportConfigJson();

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cấu hình JSON Hiện Tại'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Đây là cấu hình chuẩn dashboard_config.json tương thích 100% với phiên bản Windows:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                height: 180,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    jsonStr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Đóng'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Sao chép JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              _showMessage('Đã sao chép nội dung cấu hình vào Clipboard!');
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
        title: Text(
          'Đồng bộ Cấu hình (JSON)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: primaryText),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.share, size: 20),
            color: const Color(0xFF0284C7),
            tooltip: 'Xuất cấu hình JSON',
            onPressed: _showExportDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner giới thiệu
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(isDark ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(CupertinoIcons.arrow_2_circlepath_circle, color: Color(0xFF0284C7), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đồng bộ đa nền tảng Windows ⇄ iOS',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryText),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Ứng dụng hỗ trợ nạp trực tiếp file "dashboard_config.json" từ Windows, bao gồm danh sách máy tính, Secret Token, ứng dụng và liên kết điều khiển.',
                        style: TextStyle(fontSize: 12, color: secondaryText, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // SECTION 1: ĐỒNG BỘ ONLINE QUA URL
          Text('1. ĐỒNG BỘ ONLINE QUA URL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
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
                Text(
                  'Đường dẫn URL file dashboard_config.json:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText),
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _urlCtrl,
                  placeholder: 'https://raw.githubusercontent.com/.../dashboard_config.json',
                  padding: const EdgeInsets.all(11),
                  style: TextStyle(color: primaryText, fontSize: 13),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 16),
                      label: const Text('Dán URL', style: TextStyle(fontSize: 12)),
                      onPressed: _handlePasteUrl,
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isLoading
                          ? const CupertinoActivityIndicator(color: Colors.white, radius: 8)
                          : const Icon(CupertinoIcons.cloud_download, size: 16),
                      label: const Text('Tải & Đồng bộ Ngay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      onPressed: _isLoading ? null : _handleSyncUrl,
                    ),
                  ],
                ),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(CupertinoIcons.arrow_clockwise, color: Color(0xFF10B981)),
                  title: Text('Tự động đồng bộ khi mở app', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText)),
                  subtitle: Text('Tự tải cấu hình mới nhất từ URL trên mỗi khi khởi chạy ứng dụng', style: TextStyle(fontSize: 11, color: secondaryText)),
                  value: provider.autoSyncOnlineConfig,
                  activeColor: const Color(0xFF0284C7),
                  onChanged: (val) => provider.setAutoSyncOnlineConfig(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // SECTION 2: NHẬP TRỰC TIẾP HOẶC DÁN NỘI DUNG JSON
          Text('2. DÁN NỘI DUNG DASHBOARD_CONFIG.JSON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
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
                CupertinoTextField(
                  controller: _jsonCtrl,
                  maxLines: 8,
                  placeholder: '{\n  "token": "LANMONITOR-CHANGE-ME",\n  "hosts": [\n    {"name": "Máy cơ quan", "ip": "192.168.1.10"}\n  ]\n}',
                  padding: const EdgeInsets.all(10),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: primaryText),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardBorder),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 15),
                      label: const Text('Dán từ Clipboard', style: TextStyle(fontSize: 12)),
                      onPressed: _handlePasteClipboard,
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(CupertinoIcons.checkmark_alt, size: 16),
                      label: const Text('Áp dụng Cấu hình', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      onPressed: _handleImportJson,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // SECTION 3: KHÔI PHỤC VÀ XUẤT CẤU HÌNH
          Text('3. KHÔI PHỤC & XUẤT CẤU HÌNH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaryText)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(CupertinoIcons.arrow_counterclockwise, color: Color(0xFF0284C7)),
                  title: Text('Khôi phục từ file dashboard_config.json gốc', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText)),
                  subtitle: Text('Nạp lại các máy tính và cài đặt mặc định có sẵn trong dự án.', style: TextStyle(fontSize: 11, color: secondaryText)),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: _handleLoadBundled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(CupertinoIcons.arrow_up_doc, color: Color(0xFF10B981)),
                  title: Text('Xem & Sao chép cấu hình hiện tại (Export)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText)),
                  subtitle: Text('Sao chép file JSON chuẩn để mang sang cài đặt trên Windows.', style: TextStyle(fontSize: 11, color: secondaryText)),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: _showExportDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
