import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/host_model.dart';
import '../models/metrics_model.dart';

class LanMonitorApi {
  // Tăng thời gian chờ lên 6 giây để tương thích tối ưu với độ trễ bắt tay mạng Tailscale / DERP Relay trên 4G/LTE
  static const Duration timeoutDuration = Duration(seconds: 6);

  // Tái sử dụng HTTP Client duy nhất để giữ kết nối Persistent (HTTP Keep-Alive), tránh handshake liên tục
  static final http.Client _client = http.Client();

  /// Chuẩn hóa lỗi thân thiện với người dùng
  static String formatError(dynamic e) {
    final str = e.toString();
    if (e is TimeoutException || str.contains('TimeoutException')) {
      return 'Hết thời gian chờ kết nối (>6s)';
    }
    if (str.contains('Connection refused') || str.contains('errno = 61') || str.contains('errno = 111')) {
      return 'Không thể kết nối cổng 8765 (Agent chưa chạy hoặc sai cổng)';
    }
    if (str.contains('No route to host') || str.contains('Network is unreachable') || str.contains('SocketException')) {
      return 'Không tìm thấy thiết bị (Kiểm tra Tailscale/Wi-Fi)';
    }
    if (str.contains('Unauthorized') || str.contains('401')) {
      return 'Sai mã Secret Token bảo mật';
    }
    return str.replaceAll('Exception: ', '').replaceAll('ClientException: ', '');
  }

  /// Fetch metrics from the agent
  static Future<MetricsModel> fetchMetrics(HostModel host, String globalToken) async {
    final token = (host.token != null && host.token!.isNotEmpty) ? host.token! : globalToken;
    final uri = Uri.parse('${host.endpointUrl}/metrics');

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'X-LAN-Monitor-Token': token,
      },
    ).timeout(timeoutDuration);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      return MetricsModel.fromJson(data);
    } else if (response.statusCode == 401) {
      throw Exception('Sai mã Secret Token (Unauthorized)');
    } else {
      throw Exception('Lỗi HTTP ${response.statusCode}');
    }
  }

  /// Send control command to the agent (shutdown, reboot, sleep, run_app, open_url)
  static Future<Map<String, dynamic>> sendControl(
    HostModel host,
    String globalToken,
    String action, {
    String? appPath,
    String? url,
  }) async {
    final token = (host.token != null && host.token!.isNotEmpty) ? host.token! : globalToken;
    final uri = Uri.parse('${host.endpointUrl}/control');

    final bodyData = {
      'action': action,
      if (appPath != null) 'app_path': appPath,
      if (url != null) 'url': url,
    };

    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'X-LAN-Monitor-Token': token,
      },
      body: json.encode(bodyData),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      final msg = response.body.isNotEmpty ? response.body : 'Lỗi mã ${response.statusCode}';
      throw Exception(msg);
    }
  }
}
