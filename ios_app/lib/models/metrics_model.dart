class MetricsModel {
  final double cpuPercent;
  final int cpuCount;
  final double ramPercent;
  final double ramUsedGb;
  final double ramTotalGb;
  final double diskPercent;
  final double diskFreeGb;
  final double downloadBps;
  final double uploadBps;
  final int uptimeSec;
  final String hostname;
  final String ip;
  final String tailscaleIp;
  final List<GpuMetric> gpus;

  MetricsModel({
    required this.cpuPercent,
    required this.cpuCount,
    required this.ramPercent,
    required this.ramUsedGb,
    required this.ramTotalGb,
    required this.diskPercent,
    required this.diskFreeGb,
    required this.downloadBps,
    required this.uploadBps,
    required this.uptimeSec,
    required this.hostname,
    required this.ip,
    required this.tailscaleIp,
    required this.gpus,
  });

  factory MetricsModel.fromJson(Map<String, dynamic> json) {
    List<GpuMetric> gpuList = [];
    if (json['gpu'] is List) {
      gpuList = (json['gpu'] as List)
          .map((item) => GpuMetric.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return MetricsModel(
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      cpuCount: (json['cpu_count'] as num?)?.toInt() ?? 1,
      ramPercent: (json['ram_percent'] as num?)?.toDouble() ?? 0.0,
      ramUsedGb: (json['ram_used_gb'] as num?)?.toDouble() ?? 0.0,
      ramTotalGb: (json['ram_total_gb'] as num?)?.toDouble() ?? 0.0,
      diskPercent: (json['disk_percent'] as num?)?.toDouble() ?? 0.0,
      diskFreeGb: (json['disk_free_gb'] as num?)?.toDouble() ?? 0.0,
      downloadBps: (json['download_bps'] as num?)?.toDouble() ?? 0.0,
      uploadBps: (json['upload_bps'] as num?)?.toDouble() ?? 0.0,
      uptimeSec: (json['uptime_sec'] as num?)?.toInt() ?? 0,
      hostname: json['hostname']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      tailscaleIp: json['tailscale_ip']?.toString() ?? '',
      gpus: gpuList,
    );
  }

  String get formattedUptime {
    int days = uptimeSec ~/ 86400;
    int hours = (uptimeSec % 86400) ~/ 3600;
    int minutes = (uptimeSec % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String get formattedDownloadRate => formatSpeed(downloadBps);
  String get formattedUploadRate => formatSpeed(uploadBps);

  static String formatSpeed(double bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bps >= 1024) {
      return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${bps.toStringAsFixed(0)} B/s';
    }
  }
}

class GpuMetric {
  final String name;
  final double load;
  final double memoryUsed;
  final double memoryTotal;
  final double temperature;

  GpuMetric({
    required this.name,
    required this.load,
    required this.memoryUsed,
    required this.memoryTotal,
    required this.temperature,
  });

  factory GpuMetric.fromJson(Map<String, dynamic> json) {
    return GpuMetric(
      name: json['name']?.toString() ?? 'GPU',
      load: (json['load'] as num?)?.toDouble() ?? 0.0,
      memoryUsed: (json['memory_used'] as num?)?.toDouble() ?? 0.0,
      memoryTotal: (json['memory_total'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
