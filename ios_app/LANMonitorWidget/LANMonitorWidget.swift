import WidgetKit
import SwiftUI
import Foundation

// MARK: - Models
struct SimpleEntry: TimelineEntry {
    let date: Date
    let hostName: String
    let ip: String
    let status: String
    let isOnline: Bool
    let cpu: String
    let cpuPercent: Double
    let ram: String
    let ramPercent: Double
    let disk: String
    let diskPercent: Double
    let downloadSpeed: String
    let uploadSpeed: String
    let netSpeed: String
    let uptime: String
}

struct AgentMetricsResponse: Codable {
    let cpu_percent: Double?
    let ram_percent: Double?
    let disk_percent: Double?
    let download_bps: Double?
    let upload_bps: Double?
    let uptime_sec: Double?
    let hostname: String?
    let ip: String?
    let tailscale_ip: String?

    enum CodingKeys: String, CodingKey {
        case cpu_percent, ram_percent, disk_percent, download_bps, upload_bps, uptime_sec, hostname, ip, tailscale_ip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpu_percent = try? container.decodeIfPresent(Double.self, forKey: .cpu_percent)
        ram_percent = try? container.decodeIfPresent(Double.self, forKey: .ram_percent)
        disk_percent = try? container.decodeIfPresent(Double.self, forKey: .disk_percent)
        download_bps = try? container.decodeIfPresent(Double.self, forKey: .download_bps)
        upload_bps = try? container.decodeIfPresent(Double.self, forKey: .upload_bps)
        hostname = try? container.decodeIfPresent(String.self, forKey: .hostname)
        ip = try? container.decodeIfPresent(String.self, forKey: .ip)
        tailscale_ip = try? container.decodeIfPresent(String.self, forKey: .tailscale_ip)

        if let upDbl = try? container.decodeIfPresent(Double.self, forKey: .uptime_sec) {
            uptime_sec = upDbl
        } else if let upInt = try? container.decodeIfPresent(Int.self, forKey: .uptime_sec) {
            uptime_sec = Double(upInt)
        } else {
            uptime_sec = nil
        }
    }
}

struct CachedHostConfig {
    var hostName: String
    var ip: String
    var tailscaleIp: String
    var port: Int
    var token: String
    var cachedEntry: SimpleEntry
}

// MARK: - Helpers
func formatWidgetSpeed(_ bps: Double) -> String {
    if bps < 1024 {
        return String(format: "%.0f B/s", bps)
    } else if bps < 1024 * 1024 {
        return String(format: "%.1f KB/s", bps / 1024.0)
    } else if bps < 1024 * 1024 * 1024 {
        return String(format: "%.1f MB/s", bps / (1024.0 * 1024.0))
    } else {
        return String(format: "%.1f GB/s", bps / (1024.0 * 1024.0 * 1024.0))
    }
}

func formatWidgetUptime(_ seconds: Double) -> String {
    let totalSec = Int(seconds)
    if totalSec <= 0 { return "--" }
    let days = totalSec / 86400
    let hours = (totalSec % 86400) / 3600
    let minutes = (totalSec % 3600) / 60
    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

// MARK: - Provider
struct Provider: TimelineProvider {
    private let suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app"]

    func placeholder(in context: Context) -> SimpleEntry {
        loadLocalCache().cachedEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(loadLocalCache().cachedEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let config = loadLocalCache()
        fetchLiveMetrics(config: config) { entry in
            let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
            let timeline = Timeline(entries: [entry], policy: .after(nextDate))
            completion(timeline)
        }
    }

    // MARK: - Network Fetching (Gas Manager Architecture)
    private func fetchLiveMetrics(config: CachedHostConfig, completion: @escaping (SimpleEntry) -> Void) {
        let targetIp = config.ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetIp.isEmpty && targetIp != "--" && targetIp != "127.0.0.1" else {
            completion(config.cachedEntry)
            return
        }

        // 1. Thử gửi HTTP request trực tiếp tới IP LAN
        executeMetricRequest(ip: targetIp, port: config.port, token: config.token) { result in
            if let entry = result {
                self.saveCache(config: config, entry: entry)
                completion(entry)
                return
            }

            // 2. Nếu IP LAN không phản hồi và có IP Tailscale khác IP LAN, thử tiếp Tailscale
            let tsIp = config.tailscaleIp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tsIp.isEmpty && tsIp != targetIp && tsIp != "--" {
                self.executeMetricRequest(ip: tsIp, port: config.port, token: config.token) { tsResult in
                    if let tsEntry = tsResult {
                        self.saveCache(config: config, entry: tsEntry)
                        completion(tsEntry)
                        return
                    }
                    let offlineEntry = self.makeOfflineEntry(config: config)
                    self.saveCache(config: config, entry: offlineEntry)
                    completion(offlineEntry)
                }
            } else {
                let offlineEntry = self.makeOfflineEntry(config: config)
                self.saveCache(config: config, entry: offlineEntry)
                completion(offlineEntry)
            }
        }
    }

    private func executeMetricRequest(ip: String, port: Int, token: String, completion: @escaping (SimpleEntry?) -> Void) {
        guard let url = URL(string: "http://\(ip):\(port)/metrics") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-LAN-Monitor-Token")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.5
        config.timeoutIntervalForResource = 3.5
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }

            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(nil)
                return
            }

            do {
                let metrics = try JSONDecoder().decode(AgentMetricsResponse.self, from: data)
                let cpuVal = metrics.cpu_percent ?? 0.0
                let ramVal = metrics.ram_percent ?? 0.0
                let diskVal = metrics.disk_percent ?? 0.0
                let downBps = metrics.download_bps ?? 0.0
                let upBps = metrics.upload_bps ?? 0.0
                let uptimeSec = metrics.uptime_sec ?? 0.0

                let entry = SimpleEntry(
                    date: Date(),
                    hostName: metrics.hostname ?? ip,
                    ip: ip,
                    status: "Online",
                    isOnline: true,
                    cpu: String(format: "%.0f%%", cpuVal),
                    cpuPercent: cpuVal,
                    ram: String(format: "%.0f%%", ramVal),
                    ramPercent: ramVal,
                    disk: String(format: "%.0f%%", diskVal),
                    diskPercent: diskVal,
                    downloadSpeed: "↓ " + formatWidgetSpeed(downBps),
                    uploadSpeed: "↑ " + formatWidgetSpeed(upBps),
                    netSpeed: formatWidgetSpeed(downBps),
                    uptime: formatWidgetUptime(uptimeSec)
                )
                completion(entry)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    private func makeOfflineEntry(config: CachedHostConfig) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            hostName: config.hostName.isEmpty ? "PC" : config.hostName,
            ip: config.ip.isEmpty ? "--" : config.ip,
            status: "Mất kết nối",
            isOnline: false,
            cpu: "--",
            cpuPercent: 0.0,
            ram: "--",
            ramPercent: 0.0,
            disk: "--",
            diskPercent: 0.0,
            downloadSpeed: "↓ --",
            uploadSpeed: "↑ --",
            netSpeed: "--",
            uptime: "--"
        )
    }

    // MARK: - Cache & Storage
    private func loadLocalCache() -> CachedHostConfig {
        var loadedDict: [String: Any] = [:]

        // 1. Ưu tiên đọc từ App Group UserDefaults
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite), let h = defs.string(forKey: "widget_host"), !h.isEmpty {
                for key in ["widget_host", "widget_ip", "widget_tailscale_ip", "widget_token", "widget_status", "widget_down_speed", "widget_up_speed", "widget_net_speed", "widget_uptime"] {
                    if let val = defs.string(forKey: key) { loadedDict[key] = val }
                }
                for key in ["widget_cpu_val", "widget_ram_val", "widget_disk_val", "widget_last_updated"] {
                    if defs.object(forKey: key) != nil { loadedDict[key] = defs.double(forKey: key) }
                }
                if defs.object(forKey: "widget_port") != nil {
                    loadedDict["widget_port"] = defs.integer(forKey: "widget_port")
                }
                if defs.object(forKey: "widget_is_online") != nil {
                    loadedDict["widget_is_online"] = defs.bool(forKey: "widget_is_online")
                }
                break
            }
        }

        // 2. Dự phòng: Đọc từ tệp widget_data.json trong App Group shared container
        if loadedDict.isEmpty {
            for suite in suiteNames {
                if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
                    let fileURL = containerURL.appendingPathComponent("widget_data.json")
                    if let data = try? Data(contentsOf: fileURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        loadedDict = json
                        break
                    }
                }
            }
        }

        // 3. Dự phòng cấp cuối: Đọc từ UserDefaults.standard
        if loadedDict.isEmpty {
            let defs = UserDefaults.standard
            if let h = defs.string(forKey: "widget_host") ?? defs.string(forKey: "flutter.widget_host"), !h.isEmpty {
                loadedDict["widget_host"] = h
                loadedDict["widget_ip"] = defs.string(forKey: "widget_ip") ?? defs.string(forKey: "flutter.widget_ip")
                loadedDict["widget_tailscale_ip"] = defs.string(forKey: "widget_tailscale_ip") ?? defs.string(forKey: "flutter.widget_tailscale_ip")
                loadedDict["widget_token"] = defs.string(forKey: "widget_token") ?? defs.string(forKey: "flutter.widget_token")
                loadedDict["widget_port"] = defs.integer(forKey: "widget_port") != 0 ? defs.integer(forKey: "widget_port") : defs.integer(forKey: "flutter.widget_port")
                loadedDict["widget_status"] = defs.string(forKey: "widget_status") ?? defs.string(forKey: "flutter.widget_status")
                loadedDict["widget_is_online"] = (defs.object(forKey: "widget_is_online") as? NSNumber)?.boolValue ?? (defs.object(forKey: "flutter.widget_is_online") as? NSNumber)?.boolValue
                loadedDict["widget_cpu_val"] = defs.double(forKey: "widget_cpu_val") > 0 ? defs.double(forKey: "widget_cpu_val") : defs.double(forKey: "flutter.widget_cpu_val")
                loadedDict["widget_ram_val"] = defs.double(forKey: "widget_ram_val") > 0 ? defs.double(forKey: "widget_ram_val") : defs.double(forKey: "flutter.widget_ram_val")
                loadedDict["widget_disk_val"] = defs.double(forKey: "widget_disk_val") > 0 ? defs.double(forKey: "widget_disk_val") : defs.double(forKey: "flutter.widget_disk_val")
                loadedDict["widget_down_speed"] = defs.string(forKey: "widget_down_speed") ?? defs.string(forKey: "flutter.widget_down_speed")
                loadedDict["widget_up_speed"] = defs.string(forKey: "widget_up_speed") ?? defs.string(forKey: "flutter.widget_up_speed")
                loadedDict["widget_net_speed"] = defs.string(forKey: "widget_net_speed") ?? defs.string(forKey: "flutter.widget_net_speed")
                loadedDict["widget_uptime"] = defs.string(forKey: "widget_uptime") ?? defs.string(forKey: "flutter.widget_uptime")
                loadedDict["widget_last_updated"] = (defs.object(forKey: "widget_last_updated") as? NSNumber)?.doubleValue ?? (defs.object(forKey: "flutter.widget_last_updated") as? NSNumber)?.doubleValue
            }
        }

        let host = loadedDict["widget_host"] as? String ?? "LAN Monitor"
        let ip = loadedDict["widget_ip"] as? String ?? "--"
        let tailscaleIp = loadedDict["widget_tailscale_ip"] as? String ?? ""
        let portVal = loadedDict["widget_port"] as? Int ?? ((loadedDict["widget_port"] as? NSNumber)?.intValue ?? 8765)
        let token = loadedDict["widget_token"] as? String ?? ""

        if loadedDict.isEmpty {
            let emptyEntry = SimpleEntry(
                date: Date(),
                hostName: "Chưa kết nối",
                ip: "Mở app để đồng bộ",
                status: "Chờ đồng bộ",
                isOnline: false,
                cpu: "--",
                cpuPercent: 0.0,
                ram: "--",
                ramPercent: 0.0,
                disk: "--",
                diskPercent: 0.0,
                downloadSpeed: "↓ --",
                uploadSpeed: "↑ --",
                netSpeed: "--",
                uptime: "--"
            )
            return CachedHostConfig(hostName: host, ip: ip, tailscaleIp: tailscaleIp, port: portVal, token: token, cachedEntry: emptyEntry)
        }

        let isOnlinePref: Bool
        if let val = loadedDict["widget_is_online"] as? Bool {
            isOnlinePref = val
        } else if let num = loadedDict["widget_is_online"] as? NSNumber {
            isOnlinePref = num.boolValue
        } else {
            isOnlinePref = false
        }

        let lastUpdatedMs: Double
        if let val = loadedDict["widget_last_updated"] as? Double {
            lastUpdatedMs = val
        } else if let num = loadedDict["widget_last_updated"] as? NSNumber {
            lastUpdatedMs = num.doubleValue
        } else {
            lastUpdatedMs = 0
        }

        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let isStale = (lastUpdatedMs > 0) && ((nowMs - lastUpdatedMs) > 300000)
        let effectiveOnline = isOnlinePref && !isStale

        let statusText = effectiveOnline ? "Online" : (isStale ? "Mất kết nối (Quá hạn)" : (loadedDict["widget_status"] as? String ?? "Mất kết nối"))

        let cpuVal: Double = effectiveOnline ? ((loadedDict["widget_cpu_val"] as? Double) ?? ((loadedDict["widget_cpu_val"] as? NSNumber)?.doubleValue ?? 0.0)) : 0.0
        let ramVal: Double = effectiveOnline ? ((loadedDict["widget_ram_val"] as? Double) ?? ((loadedDict["widget_ram_val"] as? NSNumber)?.doubleValue ?? 0.0)) : 0.0
        let diskVal: Double = effectiveOnline ? ((loadedDict["widget_disk_val"] as? Double) ?? ((loadedDict["widget_disk_val"] as? NSNumber)?.doubleValue ?? 0.0)) : 0.0
        let downSpeed: String = effectiveOnline ? (loadedDict["widget_down_speed"] as? String ?? "↓ 0 B/s") : "↓ --"
        let upSpeed: String = effectiveOnline ? (loadedDict["widget_up_speed"] as? String ?? "↑ 0 B/s") : "↑ --"
        let netSpeed: String = effectiveOnline ? (loadedDict["widget_net_speed"] as? String ?? "0 B/s") : "--"
        let uptime: String = effectiveOnline ? (loadedDict["widget_uptime"] as? String ?? "--") : "--"

        let entry = SimpleEntry(
            date: Date(),
            hostName: host,
            ip: ip,
            status: statusText,
            isOnline: effectiveOnline,
            cpu: effectiveOnline ? String(format: "%.0f%%", cpuVal) : "--",
            cpuPercent: cpuVal,
            ram: effectiveOnline ? String(format: "%.0f%%", ramVal) : "--",
            ramPercent: ramVal,
            disk: effectiveOnline ? String(format: "%.0f%%", diskVal) : "--",
            diskPercent: diskVal,
            downloadSpeed: downSpeed,
            uploadSpeed: upSpeed,
            netSpeed: netSpeed,
            uptime: uptime
        )

        return CachedHostConfig(hostName: host, ip: ip, tailscaleIp: tailscaleIp, port: portVal, token: token, cachedEntry: entry)
    }

    private func saveCache(config: CachedHostConfig, entry: SimpleEntry) {
        let timestamp = Date().timeIntervalSince1970 * 1000.0
        let dict: [String: Any] = [
            "widget_host": entry.hostName,
            "widget_ip": entry.ip,
            "widget_tailscale_ip": config.tailscaleIp,
            "widget_port": config.port,
            "widget_token": config.token,
            "widget_is_online": entry.isOnline,
            "widget_status": entry.status,
            "widget_cpu_val": entry.cpuPercent,
            "widget_ram_val": entry.ramPercent,
            "widget_disk_val": entry.diskPercent,
            "widget_down_speed": entry.downloadSpeed,
            "widget_up_speed": entry.uploadSpeed,
            "widget_net_speed": entry.netSpeed,
            "widget_uptime": entry.uptime,
            "widget_last_updated": timestamp
        ]

        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
                for (k, v) in dict {
                    defs.set(v, forKey: k)
                }
                defs.synchronize()
            }
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
                let fileURL = containerURL.appendingPathComponent("widget_data.json")
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
}

// MARK: - Widget Theme (Light & Dark Mode)
struct WidgetTheme {
    let background: Color
    let cardBackground: Color
    let titleColor: Color
    let subtitleColor: Color
    let dividerColor: Color
    let iconTintColor: Color
    let cpuColor: Color
    let ramColor: Color
    let diskColor: Color
    let speedColor: Color
    let onlineColor: Color
    let offlineColor: Color

    static func current(for scheme: ColorScheme) -> WidgetTheme {
        let online = Color(red: 16/255, green: 185/255, blue: 129/255) // Emerald 500
        let offline = Color(red: 239/255, green: 68/255, blue: 68/255) // Red 500

        if scheme == .dark {
            return WidgetTheme(
                background: Color(red: 15/255, green: 23/255, blue: 42/255), // #0F172A (Slate 900)
                cardBackground: Color(red: 30/255, green: 41/255, blue: 59/255), // #1E293B (Slate 800)
                titleColor: Color(red: 248/255, green: 250/255, blue: 252/255), // #F8FAFC
                subtitleColor: Color(red: 148/255, green: 163/255, blue: 184/255), // #94A3B8 (Slate 400)
                dividerColor: Color.white.opacity(0.12),
                iconTintColor: Color(red: 56/255, green: 189/255, blue: 248/255), // Sky 400
                cpuColor: Color(red: 56/255, green: 189/255, blue: 248/255), // Sky 400
                ramColor: Color(red: 251/255, green: 191/255, blue: 36/255), // Amber 400
                diskColor: Color(red: 52/255, green: 211/255, blue: 153/255), // Emerald 400
                speedColor: Color(red: 56/255, green: 189/255, blue: 248/255),
                onlineColor: online,
                offlineColor: offline
            )
        } else {
            return WidgetTheme(
                background: Color(red: 248/255, green: 250/255, blue: 252/255), // #F8FAFC (Slate 50)
                cardBackground: Color.white,
                titleColor: Color(red: 15/255, green: 23/255, blue: 42/255), // #0F172A (Slate 900)
                subtitleColor: Color(red: 100/255, green: 116/255, blue: 139/255), // #64748B (Slate 500)
                dividerColor: Color.black.opacity(0.08),
                iconTintColor: Color(red: 2/255, green: 132/255, blue: 199/255), // Sky 600
                cpuColor: Color(red: 2/255, green: 132/255, blue: 199/255), // Sky 600
                ramColor: Color(red: 217/255, green: 119/255, blue: 6/255), // Amber 600
                diskColor: Color(red: 5/255, green: 150/255, blue: 105/255), // Emerald 600
                speedColor: Color(red: 2/255, green: 132/255, blue: 199/255),
                onlineColor: online,
                offlineColor: offline
            )
        }
    }
}

// MARK: - Views
struct MetricBar: View {
    let title: String
    let value: String
    let percent: Double
    let tintColor: Color
    let labelColor: Color
    var isOnline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(labelColor)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isOnline ? tintColor : labelColor)
            }
            ProgressView(value: min(max(percent / 100.0, 0.0), 1.0))
                .progressViewStyle(LinearProgressViewStyle(tint: isOnline ? tintColor : labelColor.opacity(0.25)))
        }
    }
}

struct SmallWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var statusColor: Color {
        entry.isOnline ? theme.onlineColor : theme.offlineColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(entry.hostName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.titleColor)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11))
                    .foregroundColor(entry.isOnline ? theme.iconTintColor : theme.offlineColor)
            }

            Divider().background(theme.dividerColor)

            MetricBar(title: "CPU", value: entry.cpu, percent: entry.cpuPercent, tintColor: theme.cpuColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)
            MetricBar(title: "RAM", value: entry.ram, percent: entry.ramPercent, tintColor: theme.ramColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)
            MetricBar(title: "Ổ ĐĨA", value: entry.disk, percent: entry.diskPercent, tintColor: theme.diskColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)

            Spacer(minLength: 0)

            HStack {
                Text(entry.status)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                Spacer()
                Text(entry.netSpeed)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(entry.isOnline ? theme.speedColor : theme.subtitleColor)
            }
        }
    }
}

struct MediumWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var statusColor: Color {
        entry.isOnline ? theme.onlineColor : theme.offlineColor
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(entry.hostName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.titleColor)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(entry.ip)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.subtitleColor)
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(theme.subtitleColor)
                    Text(entry.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 10) {
                    Text(entry.downloadSpeed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(entry.isOnline ? theme.diskColor : theme.subtitleColor)
                    Text(entry.uploadSpeed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(entry.isOnline ? theme.speedColor : theme.subtitleColor)
                }

                Text(entry.isOnline ? "Uptime: \(entry.uptime)" : "Trạng thái: Ngoại tuyến")
                    .font(.system(size: 9))
                    .foregroundColor(theme.subtitleColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(theme.dividerColor)

            VStack(spacing: 6) {
                MetricBar(title: "CPU", value: entry.cpu, percent: entry.cpuPercent, tintColor: theme.cpuColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)
                MetricBar(title: "RAM", value: entry.ram, percent: entry.ramPercent, tintColor: theme.ramColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)
                MetricBar(title: "Ổ ĐĨA", value: entry.disk, percent: entry.diskPercent, tintColor: theme.diskColor, labelColor: theme.subtitleColor, isOnline: entry.isOnline)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Entry View with iOS 17/18 containerBackground & Dynamic Light/Dark Mode
struct LANMonitorWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = WidgetTheme.current(for: colorScheme)
        Group {
            if family == .systemMedium {
                MediumWidgetView(entry: entry, theme: theme)
            } else {
                SmallWidgetView(entry: entry, theme: theme)
            }
        }
        .padding(12)
        .widgetBackground(theme.background)
    }
}

// iOS 17/18 containerBackground compatibility extension (matched with GasWidget)
extension View {
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            background(backgroundView)
        }
    }
}

// MARK: - Widget
struct LANMonitorWidget: Widget {
    let kind: String = "LANMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LANMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LAN Monitor")
        .description("Giám sát CPU, RAM, Ổ đĩa PC theo thời gian thực.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle
@main
struct LANMonitorWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        LANMonitorWidget()
    }
}
