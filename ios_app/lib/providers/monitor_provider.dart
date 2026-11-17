import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_model.dart';
import '../models/metrics_model.dart';
import '../services/lan_monitor_api.dart';

class MonitorProvider extends ChangeNotifier {
  List<HostModel> _hosts = [];
  String _globalToken = 'LANMONITOR-CHANGE-ME';
  int _refreshInterval = 2; // seconds
  bool _isAutoRefresh = true;
  bool _hideOffline = false;
  Timer? _timer;

  // Cấu hình đồng bộ online từ URL
  String? _configSyncUrl;
  bool _autoSyncOnlineConfig = false;

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
  bool get hideOffline => _hideOffline;
  List<HostModel> get displayedHosts {
    if (!_hideOffline) return _hosts;
    return _hosts.where((h) => h.isOnline != false).toList();
  }
  String get globalToken => _globalToken;
  int get refreshInterval => _refreshInterval;
  bool get isAutoRefresh => _isAutoRefresh;
  Map<String, String> get customApps => _customApps;
  Map<String, String> get customLinks => _customLinks;
  String? get configSyncUrl => _configSyncUrl;
  bool get autoSyncOnlineConfig => _autoSyncOnlineConfig;

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
    _hideOffline = prefs.getBool('hide_offline') ?? false;
    _configSyncUrl = prefs.getString('config_sync_url') ??
        'https://gist.githubusercontent.com/nhdien07122012/f540d4882c4c87e2dc799975faa57a03/raw/dashboard_config.json';
    _autoSyncOnlineConfig = prefs.getBool('auto_sync_online_config') ?? false;

    final hostsJson = prefs.getString('hosts_list');
    if (hostsJson != null && hostsJson.isNotEmpty) {
      try {
        final List list = json.decode(hostsJson);
        _hosts = list.map((e) => HostModel.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading hosts: $e');
      }
    }

    // Tự động loại bỏ hoàn toàn các máy mẫu cũ không hoạt động (192.168.1.10 và 100.100.100.100)
    _hosts.removeWhere((h) =>
      h.name == 'Máy cơ quan' ||
      h.name.contains('Talescale-Máy') ||
      h.ip == '192.168.1.10' ||
      h.ip == '100.100.100.100' ||
      h.id == '1' ||
      h.id == '2' ||
      h.id == 'host_lan'
    );

    // Khởi tạo máy tính mặc định nếu danh sách trống (IP Tailscale 100.66.18.111)
    if (_hosts.isEmpty) {
      _hosts = [
        HostModel(
          id: 'host_tailscale',
          name: 'Máy tính (Tailscale)',
          ip: '100.66.18.111',
          port: 8765,
          token: _globalToken,
        ),
      ];
      _saveHostsToPrefs();
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
    _startTimer();
    refreshAll();

    // Tự động đồng bộ online từ URL nếu được kích hoạt
    if (_autoSyncOnlineConfig && _configSyncUrl != null && _configSyncUrl!.isNotEmpty) {
      unawaited(syncConfigFromUrl(_configSyncUrl!, silent: true));
    }
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

  void setHideOffline(bool val) async {
    _hideOffline = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_offline', val);
    notifyListeners();
  }

  void toggleHideOffline() {
    setHideOffline(!_hideOffline);
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
    notifyListeners();
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
    notifyListeners();
  }

  void clearMockHosts() {
    _hosts.removeWhere((h) =>
      h.name == 'Máy cơ quan' ||
      h.name.contains('Talescale-Máy') ||
      h.ip == '192.168.1.10' ||
      h.ip == '100.100.100.100' ||
      h.id == '1' ||
      h.id == '2' ||
      h.id == 'host_lan'
    );
    if (_hosts.isEmpty) {
      _hosts.add(HostModel(
        id: 'host_tailscale',
        name: 'Máy tính (Tailscale)',
        ip: '100.66.18.111',
        port: 8765,
        token: _globalToken,
      ));
    }
    _saveHostsToPrefs();
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

  // MARK: - Đồng bộ Cấu hình (dashboard_config.json)
  Future<void> setConfigSyncUrl(String url) async {
    _configSyncUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config_sync_url', _configSyncUrl!);
    notifyListeners();
  }

  Future<void> setAutoSyncOnlineConfig(bool val) async {
    _autoSyncOnlineConfig = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync_online_config', val);
    notifyListeners();
  }

  Future<Map<String, int>> importConfigJson(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    int addedHosts = 0;
    int addedApps = 0;
    int addedLinks = 0;

    // 1. Mã Secret Token
    if (config['token'] != null && config['token'].toString().isNotEmpty) {
      _globalToken = config['token'].toString().trim();
      await prefs.setString('global_token', _globalToken);
    }

    // 2. Danh sách máy tính (hosts)
    if (config['hosts'] is List) {
      final List rawList = config['hosts'];
      final List<HostModel> parsed = [];
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item is Map) {
          final name = item['name']?.toString() ?? 'PC ${i + 1}';
          final ip = item['ip']?.toString() ?? '127.0.0.1';
          final port = (item['port'] as num?)?.toInt() ?? 8765;
          final token = item['token']?.toString();
          parsed.add(HostModel(
            id: item['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}_$i',
            name: name,
            ip: ip,
            port: port,
            token: token,
          ));
        }
      }
      if (parsed.isNotEmpty) {
        _hosts = parsed;
        await _saveHostsToPrefs();
        addedHosts = parsed.length;
      }
    }

    // 3. Danh sách apps điều khiển nhanh
    if (config['apps'] is Map) {
      _customApps = Map<String, String>.from(
        (config['apps'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
      );
      await prefs.setString('custom_apps', json.encode(_customApps));
      addedApps = _customApps.length;
    }

    // 4. Danh sách web links mở nhanh
    if (config['links'] is Map) {
      _customLinks = Map<String, String>.from(
        (config['links'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
      );
      await prefs.setString('custom_links', json.encode(_customLinks));
      addedLinks = _customLinks.length;
    }

    // 5. Cấu hình ẩn máy Offline (giống bản Windows)
    if (config['hide_offline'] != null && config['hide_offline'] is bool) {
      _hideOffline = config['hide_offline'] as bool;
      await prefs.setBool('hide_offline', _hideOffline);
    }

    notifyListeners();
    refreshAll();

    return {
      'hosts': addedHosts,
      'apps': addedApps,
      'links': addedLinks,
    };
  }

  Future<Map<String, int>> syncConfigFromUrl(String url, {bool silent = false}) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      throw Exception('Địa chỉ URL cấu hình không được để trống.');
    }

    final res = await http.get(Uri.parse(cleanUrl)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Không thể tải file từ URL (Mã HTTP ${res.statusCode})');
    }

    final data = json.decode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw Exception('Nội dung file không đúng cấu trúc JSON hợp lệ.');
    }

    await setConfigSyncUrl(cleanUrl);
    return await importConfigJson(data);
  }

  Future<Map<String, int>> loadBundledConfig() async {
    try {
      final str = await rootBundle.loadString('assets/dashboard_config.json');
      final data = json.decode(str) as Map<String, dynamic>;
      return await importConfigJson(data);
    } catch (e) {
      throw Exception('Lỗi đọc file cấu hình gốc: $e');
    }
  }

  String exportConfigJson() {
    final map = <String, dynamic>{
      'token': _globalToken,
      'theme': 'dark',
      'hosts': _hosts.map((h) => {
        'name': h.name,
        'ip': h.cleanIp,
        if (h.port != 8765) 'port': h.port,
        if (h.token != null && h.token!.isNotEmpty) 'token': h.token,
      }).toList(),
      'apps': _customApps,
      'links': _customLinks,
      'notify_offline': true,
      'hide_offline': _hideOffline,
      'minimal_style': 'digital_pill',
      'minimal_layout': 'vertical',
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
