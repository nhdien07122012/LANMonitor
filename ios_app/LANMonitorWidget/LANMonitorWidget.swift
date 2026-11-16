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
        let nextDate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextDate))
        completion(timeline)
    }

    private func createDefaultEntry() -> SimpleEntry {
        let defaults = UserDefaults(suiteName: "group.com.lanmonitor.lanMonitor") ?? UserDefaults(suiteName: "group.com.lanmonitor.app") ?? UserDefaults.standard
        let host = defaults.string(forKey: "widget_host") ?? defaults.string(forKey: "flutter.widget_host") ?? "DELL5548"
        let ip = defaults.string(forKey: "widget_ip") ?? defaults.string(forKey: "flutter.widget_ip") ?? "100.66.18.111"
        let cpuValRaw = defaults.double(forKey: "widget_cpu_val")
        let cpuVal = cpuValRaw > 0 ? cpuValRaw : (defaults.double(forKey: "flutter.widget_cpu_val") > 0 ? defaults.double(forKey: "flutter.widget_cpu_val") : 19.0)
        let ramValRaw = defaults.double(forKey: "widget_ram_val")
        let ramVal = ramValRaw > 0 ? ramValRaw : (defaults.double(forKey: "flutter.widget_ram_val") > 0 ? defaults.double(forKey: "flutter.widget_ram_val") : 82.0)
        let diskValRaw = defaults.double(forKey: "widget_disk_val")
        let diskVal = diskValRaw > 0 ? diskValRaw : (defaults.double(forKey: "flutter.widget_disk_val") > 0 ? defaults.double(forKey: "flutter.widget_disk_val") : 83.0)

        return SimpleEntry(
            date: Date(),
            hostName: host,
            ip: ip,
            status: "Online",
            isOnline: true,
            cpu: "\(Int(cpuVal))%",
            cpuPercent: cpuVal,
            ram: "\(Int(ramVal))%",
            ramPercent: ramVal,
            disk: "\(Int(diskVal))%",
            diskPercent: diskVal,
            downloadSpeed: "↓ 7.5 KB/s",
            uploadSpeed: "↑ 183.4 KB/s",
            netSpeed: "7.5 KB/s",
            uptime: "16d 2h"
        )
    }
}

// MARK: - Views
struct MetricBar: View {
    let title: String
    let value: String
    let percent: Double
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tintColor)
            }
            ProgressView(value: min(max(percent / 100.0, 0.0), 1.0))
                .progressViewStyle(LinearProgressViewStyle(tint: tintColor))
        }
    }
}

struct SmallWidgetView: View {
    var entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                    .frame(width: 7, height: 7)
                Text(entry.hostName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 2/255, green: 132/255, blue: 199/255))
            }

            Divider().background(Color.white.opacity(0.15))

            MetricBar(title: "CPU", value: entry.cpu, percent: entry.cpuPercent, tintColor: Color(red: 56/255, green: 189/255, blue: 248/255))
            MetricBar(title: "RAM", value: entry.ram, percent: entry.ramPercent, tintColor: Color(red: 251/255, green: 191/255, blue: 36/255))
            MetricBar(title: "Ổ ĐĨA", value: entry.disk, percent: entry.diskPercent, tintColor: Color(red: 52/255, green: 211/255, blue: 153/255))

            Spacer(minLength: 0)

            HStack {
                Text(entry.status)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                Spacer()
                Text(entry.netSpeed)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(red: 56/255, green: 189/255, blue: 248/255))
            }
        }
    }
}

struct MediumWidgetView: View {
    var entry: SimpleEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                        .frame(width: 8, height: 8)
                    Text(entry.hostName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Text(entry.ip)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))

                Spacer()

                HStack(spacing: 10) {
                    Text(entry.downloadSpeed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 52/255, green: 211/255, blue: 153/255))
                    Text(entry.uploadSpeed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 56/255, green: 189/255, blue: 248/255))
                }

                Text("Uptime: \(entry.uptime)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(Color.white.opacity(0.15))

            VStack(spacing: 6) {
                MetricBar(title: "CPU", value: entry.cpu, percent: entry.cpuPercent, tintColor: Color(red: 56/255, green: 189/255, blue: 248/255))
                MetricBar(title: "RAM", value: entry.ram, percent: entry.ramPercent, tintColor: Color(red: 251/255, green: 191/255, blue: 36/255))
                MetricBar(title: "Ổ ĐĨA", value: entry.disk, percent: entry.diskPercent, tintColor: Color(red: 52/255, green: 211/255, blue: 153/255))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Entry View with iOS 17/18 containerBackground
struct LANMonitorWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if family == .systemMedium {
                MediumWidgetView(entry: entry)
            } else {
                SmallWidgetView(entry: entry)
            }
        }
        .padding(12)
        .widgetBackground(Color(red: 15/255, green: 23/255, blue: 42/255))
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
