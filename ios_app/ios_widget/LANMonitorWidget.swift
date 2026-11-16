import WidgetKit
import SwiftUI
import Foundation

// MARK: - Models
struct HostWidgetItem: Codable, Identifiable {
    let id: String
    let name: String
    let ip: String
    let port: Int
    var isOnline: Bool
    var status: String
    var cpuPercent: Double
    var ramPercent: Double
    var netSpeed: String
    var uptime: String

    enum CodingKeys: String, CodingKey {
        case id, name, ip, port, status
        case isOnline = "is_online"
        case cpuPercent = "cpu"
        case ramPercent = "ram"
        case netSpeed = "net_speed"
        case uptime
    }

    init(id: String, name: String, ip: String, port: Int = 8765, isOnline: Bool = false, status: String = "Mất kết nối", cpuPercent: Double = 0.0, ramPercent: Double = 0.0, netSpeed: String = "--", uptime: String = "--") {
        self.id = id
        self.name = name
        self.ip = ip
        self.port = port
        self.isOnline = isOnline
        self.status = status
        self.cpuPercent = cpuPercent
        self.ramPercent = ramPercent
        self.netSpeed = netSpeed
        self.uptime = uptime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "PC"
        ip = (try? container.decodeIfPresent(String.self, forKey: .ip)) ?? "127.0.0.1"
        port = (try? container.decodeIfPresent(Int.self, forKey: .port)) ?? 8765
        isOnline = (try? container.decodeIfPresent(Bool.self, forKey: .isOnline)) ?? false
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? (isOnline ? "Online" : "Mất kết nối")
        cpuPercent = (try? container.decodeIfPresent(Double.self, forKey: .cpuPercent)) ?? 0.0
        ramPercent = (try? container.decodeIfPresent(Double.self, forKey: .ramPercent)) ?? 0.0
        netSpeed = (try? container.decodeIfPresent(String.self, forKey: .netSpeed)) ?? "--"
        uptime = (try? container.decodeIfPresent(String.self, forKey: .uptime)) ?? "--"
    }
}

struct AgentMetricsResponse: Codable {
    let cpu_percent: Double?
    let ram_percent: Double?
    let download_bps: Double?
    let uptime_sec: Double?

    enum CodingKeys: String, CodingKey {
        case cpu_percent, ram_percent, download_bps, uptime_sec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpu_percent = try? container.decodeIfPresent(Double.self, forKey: .cpu_percent)
        ram_percent = try? container.decodeIfPresent(Double.self, forKey: .ram_percent)
        download_bps = try? container.decodeIfPresent(Double.self, forKey: .download_bps)

        if let upDbl = try? container.decodeIfPresent(Double.self, forKey: .uptime_sec) {
            uptime_sec = upDbl
        } else if let upInt = try? container.decodeIfPresent(Int.self, forKey: .uptime_sec) {
            uptime_sec = Double(upInt)
        } else {
            uptime_sec = nil
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let hosts: [HostWidgetItem]
    let onlineCount: Int
    let totalCount: Int
}

// MARK: - Helpers
func cleanIpAddress(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
    if s.hasPrefix("https://") { s = String(s.dropFirst(8)) }
    if let slashIdx = s.firstIndex(of: "/") { s = String(s[..<slashIdx]) }
    if let colonIdx = s.firstIndex(of: ":") { s = String(s[..<colonIdx]) }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func formatWidgetSpeed(_ bps: Double) -> String {
    if bps < 1024 {
        return String(format: "%.0f B/s", bps)
    } else if bps < 1024 * 1024 {
        return String(format: "%.1f KB/s", bps / 1024.0)
    } else {
        return String(format: "%.1f MB/s", bps / (1024.0 * 1024.0))
    }
}

func formatWidgetUptime(_ seconds: Double) -> String {
    let totalSec = Int(seconds)
    if totalSec <= 0 { return "--" }
    let days = totalSec / 86400
    let hours = (totalSec % 86400) / 3600
    let minutes = (totalSec % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

// MARK: - Provider
struct Provider: TimelineProvider {
    private let suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app"]

    func placeholder(in context: Context) -> SimpleEntry {
        createPreviewEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let cached = loadCachedHosts()
        if !cached.isEmpty {
            let online = cached.filter { $0.isOnline }.count
            completion(SimpleEntry(date: Date(), hosts: cached, onlineCount: online, totalCount: cached.count))
        } else {
            completion(createPreviewEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        var hosts = loadCachedHosts()
        if hosts.isEmpty {
            hosts = getDefaultHosts()
        }

        let token = loadToken()
        let group = DispatchGroup()
        let lock = NSLock()
        var updatedHosts = hosts

        for index in 0..<hosts.count {
            group.enter()
            let host = hosts[index]
            checkHostStatus(host: host, token: token) { updated in
                lock.lock()
                updatedHosts[index] = updated
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.saveCachedHosts(hosts: updatedHosts)
            let online = updatedHosts.filter { $0.isOnline }.count
            let entry = SimpleEntry(date: Date(), hosts: updatedHosts, onlineCount: online, totalCount: updatedHosts.count)
            let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
            let timeline = Timeline(entries: [entry], policy: .after(nextDate))
            completion(timeline)
        }
    }

    private func checkHostStatus(host: HostWidgetItem, token: String, completion: @escaping (HostWidgetItem) -> Void) {
        let cleanIp = cleanIpAddress(host.ip)
        guard !cleanIp.isEmpty, cleanIp != "--", let url = URL(string: "http://\(cleanIp):\(host.port)/metrics") else {
            var res = host
            res.isOnline = false
            res.status = "Mất kết nối"
            completion(res)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-LAN-Monitor-Token")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 2.5
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
            defer { session.finishTasksAndInvalidate() }

            var res = host
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                res.isOnline = false
                res.status = "Mất kết nối"
                completion(res)
                return
            }

            if let metrics = try? JSONDecoder().decode(AgentMetricsResponse.self, from: data) {
                res.isOnline = true
                res.status = "Online"
                res.cpuPercent = metrics.cpu_percent ?? 0.0
                res.ramPercent = metrics.ram_percent ?? 0.0
                res.netSpeed = formatWidgetSpeed(metrics.download_bps ?? 0.0)
                res.uptime = formatWidgetUptime(metrics.uptime_sec ?? 0.0)
            } else {
                res.isOnline = true
                res.status = "Online"
            }
            completion(res)
        }
        task.resume()
    }

    private func createPreviewEntry() -> SimpleEntry {
        let sampleHosts = [
            HostWidgetItem(id: "1", name: "Máy cơ quan", ip: "192.168.1.10", port: 8765, isOnline: true, status: "Online", cpuPercent: 38.0, ramPercent: 65.0, netSpeed: "1.2 MB/s", uptime: "14d 6h"),
            HostWidgetItem(id: "2", name: "Talescale-Máy cơ quan", ip: "100.100.100.100", port: 8765, isOnline: true, status: "Online", cpuPercent: 42.0, ramPercent: 65.0, netSpeed: "850 KB/s", uptime: "14d 6h"),
            HostWidgetItem(id: "3", name: "Máy tính cá nhân", ip: "192.168.1.4", port: 8765, isOnline: false, status: "Mất kết nối", cpuPercent: 0.0, ramPercent: 0.0, netSpeed: "--", uptime: "--")
        ]
        return SimpleEntry(date: Date(), hosts: sampleHosts, onlineCount: 2, totalCount: 3)
    }

    private func getDefaultHosts() -> [HostWidgetItem] {
        return [
            HostWidgetItem(id: "1", name: "Máy cơ quan", ip: "192.168.1.10", port: 8765),
            HostWidgetItem(id: "2", name: "Talescale-Máy cơ quan", ip: "100.100.100.100", port: 8765),
            HostWidgetItem(id: "3", name: "SRO130 (LAN)", ip: "192.168.1.4", port: 8765)
        ]
    }

    // MARK: - Cache & Storage
    private func loadCachedHosts() -> [HostWidgetItem] {
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite), let jsonStr = defs.string(forKey: "widget_hosts_json"), let data = jsonStr.data(using: .utf8) {
                if let hosts = try? JSONDecoder().decode([HostWidgetItem].self, from: data), !hosts.isEmpty {
                    return hosts
                }
            }
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
                let fileURL = containerURL.appendingPathComponent("widget_hosts.json")
                if let data = try? Data(contentsOf: fileURL),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let jsonStr = dict["hosts_json"] as? String,
                   let jsonData = jsonStr.data(using: .utf8),
                   let hosts = try? JSONDecoder().decode([HostWidgetItem].self, from: jsonData), !hosts.isEmpty {
                    return hosts
                }
            }
        }
        return []
    }

    private func saveCachedHosts(hosts: [HostWidgetItem]) {
        guard let data = try? JSONEncoder().encode(hosts), let jsonStr = String(data: data, encoding: .utf8) else { return }
        let online = hosts.filter { $0.isOnline }.count
        let dict: [String: Any] = [
            "hosts_json": jsonStr,
            "hosts_count": hosts.count,
            "online_count": online,
            "last_updated": Date().timeIntervalSince1970 * 1000.0
        ]

        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
                defs.set(jsonStr, forKey: "widget_hosts_json")
                defs.set(hosts.count, forKey: "widget_hosts_count")
                defs.set(online, forKey: "widget_online_count")
                defs.synchronize()
            }
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
                let fileURL = containerURL.appendingPathComponent("widget_hosts.json")
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    private func loadToken() -> String {
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite), let t = defs.string(forKey: "widget_token"), !t.isEmpty {
                return t
            }
        }
        return "LANMONITOR-CHANGE-ME"
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
    let diskColor: Color
    let onlineColor: Color
    let offlineColor: Color

    static func current(for scheme: ColorScheme) -> WidgetTheme {
        let online = Color(red: 16/255, green: 185/255, blue: 129/255) // Emerald 500
        let offline = Color(red: 239/255, green: 68/255, blue: 68/255) // Red 500

        if scheme == .dark {
            return WidgetTheme(
                background: Color(red: 15/255, green: 23/255, blue: 42/255), // Slate 900
                cardBackground: Color(red: 30/255, green: 41/255, blue: 59/255), // Slate 800
                titleColor: Color(red: 248/255, green: 250/255, blue: 252/255),
                subtitleColor: Color(red: 148/255, green: 163/255, blue: 184/255), // Slate 400
                dividerColor: Color.white.opacity(0.1),
                iconTintColor: Color(red: 56/255, green: 189/255, blue: 248/255), // Sky 400
                cpuColor: Color(red: 56/255, green: 189/255, blue: 248/255),
                diskColor: Color(red: 52/255, green: 211/255, blue: 153/255),
                onlineColor: online,
                offlineColor: offline
            )
        } else {
            return WidgetTheme(
                background: Color(red: 248/255, green: 250/255, blue: 252/255), // Slate 50
                cardBackground: Color.white,
                titleColor: Color(red: 15/255, green: 23/255, blue: 42/255),
                subtitleColor: Color(red: 100/255, green: 116/255, blue: 139/255), // Slate 500
                dividerColor: Color.black.opacity(0.08),
                iconTintColor: Color(red: 2/255, green: 132/255, blue: 199/255), // Sky 600
                cpuColor: Color(red: 2/255, green: 132/255, blue: 199/255),
                diskColor: Color(red: 5/255, green: 150/255, blue: 105/255),
                onlineColor: online,
                offlineColor: offline
            )
        }
    }
}

// MARK: - Views: Host Overview Widget (Tapping opens host directly in App)
struct SmallWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var topHost: HostWidgetItem? {
        entry.hosts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11))
                    .foregroundColor(theme.iconTintColor)
                Text("LAN Monitor")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(theme.titleColor)
                Spacer()
                HStack(spacing: 3) {
                    Circle()
                        .fill(entry.onlineCount > 0 ? theme.onlineColor : theme.offlineColor)
                        .frame(width: 5, height: 5)
                    Text("\(entry.onlineCount)/\(entry.totalCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(entry.onlineCount > 0 ? theme.onlineColor : theme.offlineColor)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.cardBackground)
                .cornerRadius(6)
            }

            Divider().background(theme.dividerColor)

            // Hosts List (up to 3 items)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.hosts.prefix(3)) { host in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(host.isOnline ? theme.onlineColor : theme.offlineColor)
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(host.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(theme.titleColor)
                                .lineLimit(1)
                            Text(host.ip)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.subtitleColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        if host.isOnline {
                            Text("\(Int(host.cpuPercent))%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(theme.cpuColor)
                        } else {
                            Text("Offline")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(theme.offlineColor)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Chạm để mở thông số")
                    .font(.system(size: 8))
                    .foregroundColor(theme.subtitleColor.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7))
                    .foregroundColor(theme.subtitleColor)
            }
        }
        .widgetURL(URL(string: "lanmonitor://host?id=\(topHost?.id ?? "")&ip=\(topHost?.ip ?? "")"))
    }
}

struct MediumWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 13))
                    .foregroundColor(theme.iconTintColor)
                Text("LAN Monitor")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.titleColor)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.onlineCount > 0 ? theme.onlineColor : theme.offlineColor)
                        .frame(width: 6, height: 6)
                    Text("\(entry.onlineCount)/\(entry.totalCount) Máy Đang Chạy")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(entry.onlineCount > 0 ? theme.onlineColor : theme.offlineColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.cardBackground)
                .cornerRadius(8)
            }

            Divider().background(theme.dividerColor)

            // Hosts Grid / Cards (up to 4 hosts with individual deep links)
            VStack(spacing: 5) {
                ForEach(entry.hosts.prefix(3)) { host in
                    Link(destination: URL(string: "lanmonitor://host?id=\(host.id)&ip=\(host.ip)")!) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(host.isOnline ? theme.onlineColor : theme.offlineColor)
                                .frame(width: 7, height: 7)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(host.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(theme.titleColor)
                                    .lineLimit(1)
                                Text(host.ip)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.subtitleColor)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if host.isOnline {
                                HStack(spacing: 6) {
                                    Text("CPU \(Int(host.cpuPercent))%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(theme.cpuColor)
                                    Text(host.netSpeed != "--" && !host.netSpeed.isEmpty ? host.netSpeed : "Online")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(theme.diskColor)
                                }
                            } else {
                                Text("Mất kết nối")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(theme.offlineColor)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundColor(theme.subtitleColor.opacity(0.6))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(theme.cardBackground.opacity(0.6))
                        .cornerRadius(8)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Chạm vào máy để xem chi tiết thông số trong app")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(theme.subtitleColor)
                Spacer()
                Text("Cập nhật: " + formatTime(entry.date))
                    .font(.system(size: 8))
                    .foregroundColor(theme.subtitleColor.opacity(0.8))
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

// iOS 17/18 containerBackground compatibility extension
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
        .configurationDisplayName("Trạng thái Máy tính")
        .description("Giám sát các máy tính đang hoạt động và chạm để xem trực tiếp thông số.")
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
