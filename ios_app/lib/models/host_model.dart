import 'metrics_model.dart';

class HostModel {
  final String id;
  String name;
  String ip;
  int port;
  String? token;

  bool? isOnline; // null = connecting, true = online, false = offline
  MetricsModel? metrics;
  String? errorMessage;
  DateTime? lastChecked;

  HostModel({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 8765,
    this.token,
    this.isOnline,
    this.metrics,
    this.errorMessage,
    this.lastChecked,
  });

  String get cleanIp {
    var raw = ip.trim();
    if (raw.startsWith('http://')) raw = raw.substring(7);
    if (raw.startsWith('https://')) raw = raw.substring(8);
    if (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
    if (raw.contains(':')) {
      final parts = raw.split(':');
      raw = parts[0];
    }
    return raw;
  }

  String get endpointUrl => 'http://$cleanIp:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'token': token,
      };

  factory HostModel.fromJson(Map<String, dynamic> json) => HostModel(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name']?.toString() ?? 'PC',
        ip: json['ip']?.toString() ?? '127.0.0.1',
        port: (json['port'] as num?)?.toInt() ?? 8765,
        token: json['token']?.toString(),
      );
}
