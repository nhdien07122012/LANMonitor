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
  static const MethodChannel _widgetChannel = MethodChannel('com.lanmonitor/widget');
  List<HostModel> _hosts = [];
  String _globalToken = 'LANMONITOR-CHANGE-ME';
  int _refreshInterval = 2; // seconds
  bool _isAutoRefresh = true;
  Timer? _timer;

  // Cấu hình đồng bộ online từ URL
  String? _configSyncUrl;
  bool _autoSyncOnlineConfig = false;
  void Function(HostModel)? onOpenHostRequested;

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
  String? get configSyncUrl => _configSyncUrl;
  bool get autoSyncOnlineConfig => _autoSyncOnlineConfig;

  int get onlineCount => _hosts.where((h) => h.isOnline == true).length;
  int get offlineCount => _hosts.where((h) => h.isOnline == false).length;

  MonitorProvider() {
    _loadFromPrefs();
    _setupDeepLinkHandler();
  }

  void _setupDeepLinkHandler() {
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openHostUrl' && call.arguments is String) {
        handleOpenHostUrl(call.arguments as String);
      }
    });

    // Kiểm tra URL pending khi app khởi động từ Widget tap
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final pending = await _widgetChannel.invokeMethod<String>('getPendingOpenUrl');
        if (pending != null && pending.isNotEmpty) {
          handleOpenHostUrl(pending);
        }
      } catch (_) {}
    });
  }

  void handleOpenHostUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final hostId = uri.queryParameters['id'];
      final ip = uri.queryParameters['ip'];

      HostModel? target;
      if (hostId != null) {
        target = _hosts.cast<HostModel?>().firstWhere((h) => h?.id == hostId, orElse: () => null);
      }
      if (target == null && ip != null) {
        target = _hosts.cast<HostModel?>().firstWhere((h) => h?.ip == ip || h?.cleanIp == ip, orElse: () => null);
      }
      if (target != null && onOpenHostRequested != null) {
        onOpenHostRequested!(target);
      }
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _globalToken = prefs.getString('global_token') ?? 'LANMONITOR-CHANGE-ME';
    _refreshInterval = prefs.getInt('refresh_interval') ?? 2;
    _isAutoRefresh = prefs.getBool('is_auto_refresh') ?? true;
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

    // Khôi phục thông tin máy tính mặc định nếu danh sách trống
    if (_hosts.isEmpty) {
      _hosts = [
        HostModel(
          id: 'host_lan',
          name: 'Máy tính (LAN)',
          ip: '192.168.1.4',
          port: 8765,
          token: 'LANMONITOR-CHANGE-ME',
        ),
        HostModel(
          id: 'host_tailscale',
          name: 'Máy tính (Tailscale)',
          ip: '100.66.18.111',
          port: 8765,
          token: 'LANMONITOR-CHANGE-ME',
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
    _syncHostsToWidget();
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

    // Đồng bộ trạng thái danh sách máy mới nhất cho iOS Home Screen Widget
    _syncHostsToWidget();

    notifyListeners();
  }

  Future<void> _syncHostsToWidget() async {
    final hostsList = _hosts.map((h) => {
      'id': h.id,
      'name': h.name,
      'ip': h.cleanIp,
      'port': h.port,
      'is_online': h.isOnline == true,
      'status': h.isOnline == true ? 'Online' : (h.isOnline == false ? 'Mất kết nối' : 'Đang kết nối'),
      'cpu': h.metrics?.cpuPercent ?? 0.0,
      'ram': h.metrics?.ramPercent ?? 0.0,
      'net_speed': h.metrics?.formattedDownloadRate ?? '--',
      'uptime': h.metrics?.formattedUptime ?? '--',
    }).toList();

    final data = <String, dynamic>{
      'hosts_count': _hosts.length,
      'online_count': onlineCount,
      'hosts_json': json.encode(hostsList),
      'last_updated': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await _widgetChannel.invokeMethod('updateWidgetHosts', data);
    } catch (_) {}

    _syncPrimaryHostToWidget();
  }

  void _syncPrimaryHostToWidget() {
    if (_hosts.isNotEmpty) {
      final primary = _hosts.first;
      final hostToken = (primary.token != null && primary.token!.isNotEmpty)
          ? primary.token!
          : _globalToken;
      final tailscale = primary.metrics?.tailscaleIp ?? '';

      if (primary.isOnline == true && primary.metrics != null) {
        final m = primary.metrics!;
        _syncWidget(
          hostName: primary.name,
          ip: primary.ip,
          tailscaleIp: tailscale,
          port: primary.port,
          token: hostToken,
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
          tailscaleIp: tailscale,
          port: primary.port,
          token: hostToken,
          isOnline: false,
        );
      }
    } else {
      _syncWidget(
        hostName: 'Chưa có máy',
        ip: '--',
        port: 8765,
        isOnline: false,
      );
    }
  }

  Future<void> _syncWidget({
    required String hostName,
    required String ip,
    String tailscaleIp = '',
    int port = 8765,
    String token = '',
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
    final tokenToUse = token.isNotEmpty ? token : _globalToken;

    final data = <String, dynamic>{
      'widget_host': hostName,
      'widget_ip': ip,
      'widget_tailscale_ip': tailscaleIp,
      'widget_port': port,
      'widget_token': tokenToUse,
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
      await prefs.setString('widget_tailscale_ip', tailscaleIp);
      await prefs.setInt('widget_port', port);
      await prefs.setString('widget_token', tokenToUse);
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

    notifyListeners();
    _syncHostsToWidget();
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
      'hide_offline': false,
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
