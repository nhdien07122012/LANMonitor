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
        let cachedHosts = loadCachedHosts()
        if cachedHosts.isEmpty {
            let entry = SimpleEntry(date: Date(), hosts: [], onlineCount: 0, totalCount: 0)
            let nextDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(nextDate)))
            return
        }

        let token = loadToken()
        let lastUpdatedMs = loadLastUpdated()
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let isCacheFreshFromApp = (nowMs - lastUpdatedMs) < 180000.0 // Trong vòng 3 phút kể từ lần app đồng bộ

        let group = DispatchGroup()
        let lock = NSLock()
        var updatedHosts = cachedHosts

        for index in 0..<cachedHosts.count {
            group.enter()
            let host = cachedHosts[index]
            checkHostStatus(host: host, token: token) { updated in
                lock.lock()
                if updated.isOnline {
                    updatedHosts[index] = updated
                } else {
                    // Nếu truy vấn mạng trực tiếp từ widget bị lỗi (thường do sandbox mạng nội bộ của iOS khi widget chạy nền),
                    // nhưng app chính vừa mới đồng bộ máy đó là Online, ta giữ nguyên trạng thái Online của app
                    // để tránh chập chờn báo Offline sai lệch!
                    if isCacheFreshFromApp && host.isOnline {
                        updatedHosts[index] = host
                    } else {
                        updatedHosts[index] = updated
                    }
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.saveCachedHosts(hosts: updatedHosts)
            let online = updatedHosts.filter { $0.isOnline }.count
            let entry = SimpleEntry(date: Date(), hosts: updatedHosts, onlineCount: online, totalCount: updatedHosts.count)
            let nextDate = Calendar.current.date(byAdding: .minute, value: 2, to: Date()) ?? Date().addingTimeInterval(120)
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
                res.cpuPercent = metrics.cpu_percent ?? res.cpuPercent
                res.ramPercent = metrics.ram_percent ?? res.ramPercent
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
            HostWidgetItem(id: "host_tailscale", name: "Máy tính (Tailscale)", ip: "100.66.18.111", port: 8765, isOnline: true, status: "Online", cpuPercent: 35.0, ramPercent: 58.0, netSpeed: "1.2 MB/s", uptime: "14d 6h")
        ]
        return SimpleEntry(date: Date(), hosts: sampleHosts, onlineCount: 1, totalCount: 1)
    }

    // MARK: - Cache & Storage
    private func loadCachedHosts() -> [HostWidgetItem] {
        let keysToCheck = ["widget_hosts_json", "hosts_json"]

        // 1. Kiểm tra App Group UserDefaults
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
                for key in keysToCheck {
                    if let jsonStr = defs.string(forKey: key), let data = jsonStr.data(using: .utf8) {
                        if let hosts = try? JSONDecoder().decode([HostWidgetItem].self, from: data), !hosts.isEmpty {
                            return hosts
                        }
                    }
                }
            }
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
                let fileURL = containerURL.appendingPathComponent("widget_hosts.json")
                if let data = try? Data(contentsOf: fileURL),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for key in keysToCheck {
                        if let jsonStr = dict[key] as? String,
                           let jsonData = jsonStr.data(using: .utf8),
                           let hosts = try? JSONDecoder().decode([HostWidgetItem].self, from: jsonData), !hosts.isEmpty {
                            return hosts
                        }
                    }
                }
            }
        }

        // 2. Dự phòng Standard UserDefaults
        for key in keysToCheck {
            if let jsonStr = UserDefaults.standard.string(forKey: key), let data = jsonStr.data(using: .utf8) {
                if let hosts = try? JSONDecoder().decode([HostWidgetItem].self, from: data), !hosts.isEmpty {
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
            "widget_hosts_json": jsonStr,
            "hosts_count": hosts.count,
            "online_count": online,
            "last_updated": Date().timeIntervalSince1970 * 1000.0
        ]

        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
                defs.set(jsonStr, forKey: "widget_hosts_json")
                defs.set(jsonStr, forKey: "hosts_json")
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

        UserDefaults.standard.set(jsonStr, forKey: "widget_hosts_json")
        UserDefaults.standard.set(jsonStr, forKey: "hosts_json")
        UserDefaults.standard.synchronize()
    }

    private func loadToken() -> String {
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite), let t = defs.string(forKey: "widget_token"), !t.isEmpty {
                return t
            }
        }
        if let t = UserDefaults.standard.string(forKey: "widget_token"), !t.isEmpty {
            return t
        }
        return "LANMONITOR-CHANGE-ME"
    }

    private func loadLastUpdated() -> Double {
        for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
                let t = defs.double(forKey: "last_updated")
                if t > 0 { return t }
            }
        }
        return UserDefaults.standard.double(forKey: "last_updated")
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

// MARK: - Views: Host Overview Widget (CHỈ HIỆN MÁY ĐANG HOẠT ĐỘNG, BẢO ĐẢM KHÔNG MẤT CHỮ)
struct SmallWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var activeHosts: [HostWidgetItem] {
        entry.hosts.filter { $0.isOnline }
    }

    var topHost: HostWidgetItem? {
        activeHosts.first
    }

    var body: some View {
        Group {
            if activeHosts.isEmpty {
                emptyView
            } else if activeHosts.count == 1, let host = topHost {
                singleHostView(host: host)
            } else {
                multiHostsView
            }
        }
        .widgetURL(URL(string: topHost != nil ? "lanmonitor://host?id=\(topHost!.id)&ip=\(topHost!.ip)" : "lanmonitor://open"))
    }

    // Giao diện khi không có máy nào đang hoạt động
    private var emptyView: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.iconTintColor)
                Text("LAN Monitor")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(theme.titleColor)
                Spacer()
                Circle()
                    .fill(theme.offlineColor)
                    .frame(width: 5, height: 5)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Image(systemName: "power.circle")
                    .font(.system(size: 24))
                    .foregroundColor(theme.subtitleColor.opacity(0.8))
                Text("Không có máy online")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(theme.titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Tất cả máy đang tắt")
                    .font(.system(size: 9))
                    .foregroundColor(theme.subtitleColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                Text("Chạm để mở app")
                    .font(.system(size: 8))
                    .foregroundColor(theme.subtitleColor.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7))
                    .foregroundColor(theme.subtitleColor)
            }
        }
    }

    // Giao diện chuyên biệt khi có 1 máy đang chạy: Hiển thị đầy đủ tên, IP, CPU, tốc độ, không bao giờ bị cắt chữ
    private func singleHostView(host: HostWidgetItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.onlineColor)
                    .frame(width: 6, height: 6)
                Text("Đang chạy")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.onlineColor)
                Spacer()
                Text("\(Int(host.cpuPercent))% CPU")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(theme.cpuColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(theme.cardBackground)
                    .cornerRadius(5)
            }

            Spacer(minLength: 4)

            // Tên máy (hiển thị tối đa 2 dòng, tự co giãn nhẹ font để không bao giờ bị dấu 3 chấm ...)
            Text(host.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(theme.titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Địa chỉ IP riêng biệt 1 dòng
            Text(host.ip)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.subtitleColor)
                .padding(.top, 2)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Thông số Tốc độ mạng & Thời gian bật máy (Uptime)
            HStack(spacing: 5) {
                if host.netSpeed != "--" && !host.netSpeed.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                        Text(host.netSpeed)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(theme.diskColor)
                }
                if host.uptime != "--" && !host.uptime.isEmpty {
                    Text("•")
                        .font(.system(size: 7))
                        .foregroundColor(theme.subtitleColor)
                    Text(host.uptime)
                        .font(.system(size: 9))
                        .foregroundColor(theme.subtitleColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            // Footer gợi ý chạm
            HStack {
                Text("Chạm xem thông số")
                    .font(.system(size: 8))
                    .foregroundColor(theme.subtitleColor.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7))
                    .foregroundColor(theme.subtitleColor)
            }
        }
    }

    // Giao diện khi có từ 2 máy online trở lên: bố cục 2 dòng mỗi máy, tên dòng trên, IP dòng dưới
    private var multiHostsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.iconTintColor)
                Text("LAN Monitor")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.titleColor)
                Spacer()
                HStack(spacing: 3) {
                    Circle()
                        .fill(theme.onlineColor)
                        .frame(width: 5, height: 5)
                    Text("\(activeHosts.count) Online")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(theme.onlineColor)
                }
            }

            Divider().background(theme.dividerColor).padding(.vertical, 0)

            // Tối đa 2 máy online trên widget Small
            ForEach(activeHosts.prefix(2)) { host in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(theme.onlineColor)
                            .frame(width: 5, height: 5)
                        Text(host.name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(theme.titleColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text("\(Int(host.cpuPercent))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(theme.cpuColor)
                    }
                    HStack(spacing: 4) {
                        Text(host.ip)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.subtitleColor)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if host.netSpeed != "--" && !host.netSpeed.isEmpty {
                            Text(host.netSpeed)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(theme.diskColor)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(theme.cardBackground.opacity(0.8))
                .cornerRadius(5)
            }

            Spacer(minLength: 0)

            HStack {
                if activeHosts.count > 2 {
                    Text("+ \(activeHosts.count - 2) máy khác")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(theme.iconTintColor)
                } else {
                    Text("Chạm để mở thông số")
                        .font(.system(size: 8))
                        .foregroundColor(theme.subtitleColor.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7))
                    .foregroundColor(theme.subtitleColor)
            }
        }
    }
}

struct MediumWidgetView: View {
    var entry: SimpleEntry
    var theme: WidgetTheme

    var activeHosts: [HostWidgetItem] {
        entry.hosts.filter { $0.isOnline }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12))
                    .foregroundColor(theme.iconTintColor)
                Text("LAN Monitor")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.titleColor)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(activeHosts.isEmpty ? theme.offlineColor : theme.onlineColor)
                        .frame(width: 6, height: 6)
                    Text(activeHosts.isEmpty ? "Tất cả ngoại tuyến" : "\(activeHosts.count) Máy Đang Hoạt Động")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(activeHosts.isEmpty ? theme.offlineColor : theme.onlineColor)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(theme.cardBackground)
                .cornerRadius(6)
            }

            Divider().background(theme.dividerColor)

            if activeHosts.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "power.circle")
                            .font(.system(size: 24))
                            .foregroundColor(theme.subtitleColor.opacity(0.7))
                        Text("Không có máy tính nào đang hoạt động")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.titleColor)
                        Text("Tất cả các máy đều đang ngoại tuyến hoặc tắt nguồn")
                            .font(.system(size: 9))
                            .foregroundColor(theme.subtitleColor)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                // Danh sách tối đa 3 máy online kèm Link mở chi tiết từng máy
                VStack(spacing: 4) {
                    ForEach(activeHosts.prefix(3)) { host in
                        Link(destination: URL(string: "lanmonitor://host?id=\(host.id)&ip=\(host.ip)")!) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(theme.onlineColor)
                                    .frame(width: 7, height: 7)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(host.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(theme.titleColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(host.ip)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(theme.subtitleColor)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                HStack(spacing: 6) {
                                    Text("CPU \(Int(host.cpuPercent))%")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(theme.cpuColor)
                                    if host.ramPercent > 0 {
                                        Text("RAM \(Int(host.ramPercent))%")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(theme.subtitleColor)
                                    }
                                    if host.netSpeed != "--" && !host.netSpeed.isEmpty {
                                        Text("↓ \(host.netSpeed)")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(theme.diskColor)
                                    }
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7))
                                    .foregroundColor(theme.subtitleColor.opacity(0.7))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 7)
                            .background(theme.cardBackground.opacity(0.7))
                            .cornerRadius(7)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(activeHosts.isEmpty ? "Chạm để mở ứng dụng" : "Chạm vào máy để xem chi tiết thông số")
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
        .configurationDisplayName("Máy Đang Hoạt Động")
        .description("Chỉ hiển thị các máy tính đang hoạt động và chạm để xem trực tiếp thông số.")
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
