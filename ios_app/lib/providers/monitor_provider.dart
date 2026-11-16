import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_model.dart';
import '../models/metrics_model.dart';
import '../services/lan_monitor_api.dart';

class MonitorProvider extends ChangeNotifier {
  static const MethodChannel _widgetChannel = MethodChannel('com.lanmonitor/widget');
  List<HostModel> _hosts = [];
  String _globalToken = 'LANMONITOR-CHANGE-ME';
  int _refreshInterval = 2; // seconds
  bool _isAutoRefresh = true;
  Timer? _timer;

  // Apps and Links definitions
  Map<String, String> _customApps = {
    'Notepad': 'notepad.exe',
    'Chrome': 'chrome.exe',
    'Task Manager': 'taskmgr.exe',
  };

  Map<String, String> _customLinks = {
    'Google': 'https://google.com',
    'YouTube': 'https://youtube.com',
  };

  List<HostModel> get hosts => _hosts;
  String get globalToken => _globalToken;
  int get refreshInterval => _refreshInterval;
  bool get isAutoRefresh => _isAutoRefresh;
  Map<String, String> get customApps => _customApps;
  Map<String, String> get customLinks => _customLinks;

  int get onlineCount => _hosts.where((h) => h.isOnline == true).length;
  int get offlineCount => _hosts.where((h) => h.isOnline == false).length;

  MonitorProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _globalToken = prefs.getString('global_token') ?? 'LANMONITOR-CHANGE-ME';
    _refreshInterval = prefs.getInt('refresh_interval') ?? 2;
    _isAutoRefresh = prefs.getBool('is_auto_refresh') ?? true;

    final hostsJson = prefs.getString('hosts_list');
    if (hostsJson != null) {
      try {
        final List list = json.decode(hostsJson);
        _hosts = list.map((e) => HostModel.fromJson(e)).toList();

        // Tự động dọn sạch các thiết bị mẫu mặc định (Máy cơ quan / Talescale-Máy cơ quan)
        _hosts.removeWhere((h) =>
          h.name == 'Máy cơ quan' ||
          h.name.contains('Talescale-Máy') ||
          h.ip == '192.168.1.10' ||
          h.ip == '100.100.100.100' ||
          h.id == '1' ||
          h.id == '2'
        );
        _saveHostsToPrefs();
      } catch (e) {
        debugPrint('Error loading hosts: $e');
      }
    } else {
      // First-time app launch: start with clean empty list or single default
      _hosts = [];
    }

    final appsJson = prefs.getString('custom_apps');
    if (appsJson != null) {
      _customApps = Map<String, String>.from(json.decode(appsJson));
    }

    final linksJson = prefs.getString('custom_links');
    if (linksJson != null) {
      _customLinks = Map<String, String>.from(json.decode(linksJson));
    }

    notifyListeners();
    _syncPrimaryHostToWidget();
    _startTimer();
    refreshAll();
  }

  Future<void> _saveHostsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(_hosts.map((e) => e.toJson()).toList());
    await prefs.setString('hosts_list', jsonStr);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_isAutoRefresh && _refreshInterval > 0) {
      _timer = Timer.periodic(Duration(seconds: _refreshInterval), (_) {
        refreshAll();
      });
    }
  }

  void setAutoRefresh(bool enabled) async {
    _isAutoRefresh = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_auto_refresh', enabled);
    _startTimer();
    notifyListeners();
  }

  void setRefreshInterval(int seconds) async {
    _refreshInterval = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('refresh_interval', seconds);
    _startTimer();
    notifyListeners();
  }

  void setGlobalToken(String token) async {
    _globalToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('global_token', token);
    notifyListeners();
    refreshAll();
  }

  Future<void> refreshAll() async {
    final futures = _hosts.map((host) async {
      try {
        final metrics = await LanMonitorApi.fetchMetrics(host, _globalToken);
        host.isOnline = true;
        host.metrics = metrics;
        host.errorMessage = null;
        host.lastChecked = DateTime.now();
      } catch (e) {
        host.isOnline = false;
        host.errorMessage = e.toString().replaceAll('Exception: ', '');
        host.lastChecked = DateTime.now();
      }
    });

    await Future.wait(futures);

    // Đồng bộ trạng thái mới nhất cho iOS Home Screen Widget
    _syncPrimaryHostToWidget();

    notifyListeners();
  }

  void _syncPrimaryHostToWidget() {
    if (_hosts.isNotEmpty) {
      final primary = _hosts.first;
      if (primary.isOnline == true && primary.metrics != null) {
        final m = primary.metrics!;
        _syncWidget(
          hostName: primary.name,
          ip: primary.ip,
          isOnline: true,
          cpu: m.cpuPercent,
          ram: m.ramPercent,
          disk: m.diskPercent,
          downSpeed: '↓ ${m.formattedDownloadRate}',
          upSpeed: '↑ ${m.formattedUploadRate}',
          netSpeed: m.formattedDownloadRate,
          uptime: m.formattedUptime,
        );
      } else {
        // Mất kết nối hoặc offline: gửi tín hiệu ngắt kết nối và xóa thông số cũ
        _syncWidget(
          hostName: primary.name,
          ip: primary.ip,
          isOnline: false,
        );
      }
    } else {
      _syncWidget(
        hostName: 'Chưa có máy',
        ip: '--',
        isOnline: false,
      );
    }
  }

  Future<void> _syncWidget({
    required String hostName,
    required String ip,
    required bool isOnline,
    double cpu = 0.0,
    double ram = 0.0,
    double disk = 0.0,
    String downSpeed = '↓ --',
    String upSpeed = '↑ --',
    String netSpeed = '--',
    String uptime = '--',
  }) async {
    final status = isOnline ? 'Online' : 'Mất kết nối';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final data = <String, dynamic>{
      'widget_host': hostName,
      'widget_ip': ip,
      'widget_is_online': isOnline,
      'widget_status': status,
      'widget_cpu_val': isOnline ? cpu : 0.0,
      'widget_ram_val': isOnline ? ram : 0.0,
      'widget_disk_val': isOnline ? disk : 0.0,
      'widget_down_speed': isOnline ? downSpeed : '↓ --',
      'widget_up_speed': isOnline ? upSpeed : '↑ --',
      'widget_net_speed': isOnline ? netSpeed : '--',
      'widget_uptime': isOnline ? uptime : '--',
      'widget_last_updated': timestamp,
    };

    // 1. Gửi qua MethodChannel đến native iOS để ghi vào App Group và gọi WidgetCenter.shared.reloadAllTimelines()
    try {
      await _widgetChannel.invokeMethod('updateWidget', data);
    } catch (_) {}

    // 2. Ghi song song vào SharedPreferences làm fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_host', hostName);
      await prefs.setString('widget_ip', ip);
      await prefs.setBool('widget_is_online', isOnline);
      await prefs.setString('widget_status', status);
      await prefs.setDouble('widget_cpu_val', isOnline ? cpu : 0.0);
      await prefs.setDouble('widget_ram_val', isOnline ? ram : 0.0);
      await prefs.setDouble('widget_disk_val', isOnline ? disk : 0.0);
      await prefs.setString('widget_down_speed', isOnline ? downSpeed : '↓ --');
      await prefs.setString('widget_up_speed', isOnline ? upSpeed : '↑ --');
      await prefs.setString('widget_net_speed', isOnline ? netSpeed : '--');
      await prefs.setString('widget_uptime', isOnline ? uptime : '--');
      await prefs.setInt('widget_last_updated', timestamp);
      if (_globalToken.isNotEmpty) {
        await prefs.setString('widget_token', _globalToken);
      }
    } catch (_) {}
  }

  void addHost(HostModel host) {
    _hosts.add(host);
    _saveHostsToPrefs();
    notifyListeners();
    refreshAll();
  }

  void updateHost(HostModel host) {
    final idx = _hosts.indexWhere((h) => h.id == host.id);
    if (idx != -1) {
      _hosts[idx] = host;
      _saveHostsToPrefs();
      notifyListeners();
      refreshAll();
    }
  }

  void deleteHost(String id) {
    _hosts.removeWhere((h) => h.id == id);
    _saveHostsToPrefs();
    _syncPrimaryHostToWidget();
    notifyListeners();
  }

  void clearMockHosts() {
    _hosts.removeWhere((h) =>
      h.name == 'Máy cơ quan' ||
      h.name.contains('Talescale-Máy') ||
      h.ip == '192.168.1.10' ||
      h.ip == '100.100.100.100' ||
      h.id == '1' ||
      h.id == '2'
    );
    _saveHostsToPrefs();
    _syncPrimaryHostToWidget();
    notifyListeners();
  }

  Future<String> sendControl(HostModel host, String action, {String? appPath, String? url}) async {
    try {
      final res = await LanMonitorApi.sendControl(
        host,
        _globalToken,
        action,
        appPath: appPath,
        url: url,
      );
      return res['message']?.toString() ?? 'Lệnh gửi thành công!';
    } catch (e) {
      return 'Lỗi: ${e.toString().replaceAll('Exception: ', '')}';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
