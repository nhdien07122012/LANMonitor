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

// MARK: - Provider
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        createDefaultEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(createDefaultEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = createDefaultEntry()
        let intervalMinutes = entry.isOnline ? 3 : 1
        let nextDate = Calendar.current.date(byAdding: .minute, value: intervalMinutes, to: Date()) ?? Date().addingTimeInterval(Double(intervalMinutes * 60))
        let timeline = Timeline(entries: [entry], policy: .after(nextDate))
        completion(timeline)
    }

    private func createDefaultEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: "group.com.lanmonitor.lanMonitor") ?? UserDefaults(suiteName: "group.com.lanmonitor.app") ?? UserDefaults.standard
        let host = defaults.string(forKey: "widget_host") ?? defaults.string(forKey: "flutter.widget_host") ?? "DELL5548"
        let ip = defaults.string(forKey: "widget_ip") ?? defaults.string(forKey: "flutter.widget_ip") ?? "100.66.18.111"

        // Trạng thái kết nối từ App Group / UserDefaults
        var isOnlineFlag = true
        if let val = (defaults.object(forKey: "widget_is_online") as? NSNumber) ?? (defaults.object(forKey: "flutter.widget_is_online") as? NSNumber) {
            isOnlineFlag = val.boolValue
        }

        // Kiểm tra hạn cập nhật dữ liệu (nếu quá 5 phút = 300,000 ms thì đánh dấu ngắt kết nối tự động)
        var lastUpdatedMs: Double = 0
        if let val = (defaults.object(forKey: "widget_last_updated") as? NSNumber) ?? (defaults.object(forKey: "flutter.widget_last_updated") as? NSNumber) {
            lastUpdatedMs = val.doubleValue
        }

        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let isStale = (lastUpdatedMs > 0) && ((nowMs - lastUpdatedMs) > 300000)

        // Trạng thái online thực tế
        let effectiveOnline = isOnlineFlag && !isStale

        let statusText: String
        if !effectiveOnline {
            if isStale {
                statusText = "Mất kết nối (Quá hạn)"
            } else {
                statusText = defaults.string(forKey: "widget_status") ?? defaults.string(forKey: "flutter.widget_status") ?? "Mất kết nối"
            }
        } else {
            statusText = defaults.string(forKey: "widget_status") ?? defaults.string(forKey: "flutter.widget_status") ?? "Online"
        }

        let cpuVal: Double
        let ramVal: Double
        let diskVal: Double
        let downSpeed: String
        let upSpeed: String
        let netSpeed: String
        let uptime: String

        if effectiveOnline {
            let cpuRaw = (defaults.object(forKey: "widget_cpu_val") as? NSNumber)?.doubleValue ?? (defaults.object(forKey: "flutter.widget_cpu_val") as? NSNumber)?.doubleValue
            cpuVal = cpuRaw ?? 0.0

            let ramRaw = (defaults.object(forKey: "widget_ram_val") as? NSNumber)?.doubleValue ?? (defaults.object(forKey: "flutter.widget_ram_val") as? NSNumber)?.doubleValue
            ramVal = ramRaw ?? 0.0

            let diskRaw = (defaults.object(forKey: "widget_disk_val") as? NSNumber)?.doubleValue ?? (defaults.object(forKey: "flutter.widget_disk_val") as? NSNumber)?.doubleValue
            diskVal = diskRaw ?? 0.0

            downSpeed = defaults.string(forKey: "widget_down_speed") ?? defaults.string(forKey: "flutter.widget_down_speed") ?? "↓ 0 B/s"
            upSpeed = defaults.string(forKey: "widget_up_speed") ?? defaults.string(forKey: "flutter.widget_up_speed") ?? "↑ 0 B/s"
            netSpeed = defaults.string(forKey: "widget_net_speed") ?? defaults.string(forKey: "flutter.widget_net_speed") ?? "0 B/s"
            uptime = defaults.string(forKey: "widget_uptime") ?? defaults.string(forKey: "flutter.widget_uptime") ?? "--"
        } else {
            cpuVal = 0.0
            ramVal = 0.0
            diskVal = 0.0
            downSpeed = "↓ --"
            upSpeed = "↑ --"
            netSpeed = "--"
            uptime = "--"
        }

        return SimpleEntry(
            date: Date(),
            hostName: host,
            ip: ip,
            status: statusText,
            isOnline: effectiveOnline,
            cpu: effectiveOnline ? "\(Int(cpuVal))%" : "--",
            cpuPercent: cpuVal,
            ram: effectiveOnline ? "\(Int(ramVal))%" : "--",
            ramPercent: ramVal,
            disk: effectiveOnline ? "\(Int(diskVal))%" : "--",
            diskPercent: diskVal,
            downloadSpeed: downSpeed,
            uploadSpeed: upSpeed,
            netSpeed: netSpeed,
            uptime: uptime
        )
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
