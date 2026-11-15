import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/host_model.dart';
import '../models/metrics_model.dart';

class LanMonitorApi {
  static const Duration timeoutDuration = Duration(seconds: 3);

  /// Fetch metrics from the agent
  static Future<MetricsModel> fetchMetrics(HostModel host, String globalToken) async {
    final token = (host.token != null && host.token!.isNotEmpty) ? host.token! : globalToken;
    final uri = Uri.parse('${host.endpointUrl}/metrics');

    final response = await http.get(
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

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'X-LAN-Monitor-Token': token,
      },
      body: json.encode(bodyData),
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      final msg = response.body.isNotEmpty ? response.body : 'Lỗi mã ${response.statusCode}';
      throw Exception(msg);
    }
  }
}
