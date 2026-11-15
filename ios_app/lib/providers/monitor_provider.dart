import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_model.dart';
import '../services/lan_monitor_api.dart';

class MonitorProvider extends ChangeNotifier {
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
    if (hostsJson != null && hostsJson.isNotEmpty) {
      try {
        final List list = json.decode(hostsJson);
        _hosts = list.map((e) => HostModel.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading hosts: $e');
      }
    }

    // Default sample hosts if empty
    if (_hosts.isEmpty) {
      _hosts = [
        HostModel(id: '1', name: 'Máy cơ quan', ip: '192.168.1.10', port: 8765),
        HostModel(id: '2', name: 'Talescale-Máy cơ quan', ip: '100.100.100.100', port: 8765),
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
