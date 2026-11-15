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

  String get endpointUrl => 'http://$ip:$port';

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
