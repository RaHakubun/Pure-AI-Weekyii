import WidgetKit
import SwiftUI

private enum WeekyiiWidgetKind {
    static let main = "WeekyiiWidget"
}

struct WeekyiiWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WeekyiiWidgetProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> WeekyiiWidgetEntry {
        WeekyiiWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekyiiWidgetEntry) -> Void) {
        let snapshot = store.load() ?? .placeholder
        completion(WeekyiiWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekyiiWidgetEntry>) -> Void) {
        let snapshot = store.load() ?? .placeholder
        let entry = WeekyiiWidgetEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct WeekyiiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekyiiWidgetKind.main, provider: WeekyiiWidgetProvider()) { entry in
            WeekyiiWidgetRoot(entry: entry)
        }
        .configurationDisplayName("Weekyii")
        .description("快速查看今日任务进度与本周概览。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}

private struct WeekyiiWidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WeekyiiWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        case .accessoryInline:
            inlineLockView
        case .accessoryRectangular:
            rectangularLockView
        case .accessoryCircular:
            circularLockView
        default:
            smallView
        }
    }

    private var colors: WidgetThemePalette {
        entry.snapshot.theme.resolvedPalette(isDarkSystem: colorScheme == .dark)
    }

    private var completionText: String {
        "\(entry.snapshot.today.completedCount)/\(entry.snapshot.today.totalCount)"
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot.today.weekdaySymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                Spacer()
                Text(entry.snapshot.today.killTimeText)
                    .font(.caption2)
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.snapshot.today.completionPercent)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))
                Text("%")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                .font(.caption)
                .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                .lineLimit(2)

            Spacer(minLength: 0)

            Text("完成 \(completionText)")
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
        }
        .padding(12)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日")
                    .font(.headline)
                    .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))

                Text("\(entry.snapshot.today.completionPercent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))

                HStack(spacing: 8) {
                    chip(title: "完成", value: entry.snapshot.today.completedCount)
                    chip(title: "剩余", value: max(entry.snapshot.today.totalCount - entry.snapshot.today.completedCount, 0))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.snapshot.today.previewTasks.prefix(3)) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(zoneColor(raw: task.zoneRaw))
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.caption)
                            .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                            .lineLimit(1)
                    }
                }
                if entry.snapshot.today.previewTasks.isEmpty {
                    Text("今天没有待办")
                        .font(.caption)
                        .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekyii")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))
                Spacer()
                Text("Kill \(entry.snapshot.today.killTimeText)")
                    .font(.caption)
                    .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            }

            HStack(alignment: .center, spacing: 10) {
                Text("\(entry.snapshot.today.completionPercent)%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(widgetHex: colors.primaryHex))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                    Text("完成 \(completionText)")
                        .font(.caption)
                        .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                }
                Spacer(minLength: 0)
            }

            Divider()
                .overlay(Color(widgetHex: colors.primaryLightHex).opacity(0.35))

            Text("本周")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(entry.snapshot.weekDays.prefix(7)) { day in
                    VStack(spacing: 4) {
                        Text(day.weekdaySymbol.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
                        Text("\(day.dayNumber)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(zoneColor(raw: day.statusRaw).opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(14)
        .containerBackground(Color(widgetHex: colors.backgroundHex), for: .widget)
    }

    private var inlineLockView: some View {
        Text("今日 \(completionText)")
    }

    private var rectangularLockView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.today.completionPercent)% · \(completionText)")
                .font(.caption.weight(.semibold))
            Text(entry.snapshot.today.focusTitle ?? "暂无焦点任务")
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var circularLockView: some View {
        ZStack {
            Circle()
                .stroke(Color(widgetHex: colors.primaryLightHex).opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(entry.snapshot.today.completionPercent) / 100)
                .stroke(Color(widgetHex: colors.primaryHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(entry.snapshot.today.completionPercent)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .padding(3)
    }

    private func chip(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(widgetHex: colors.textSecondaryHex))
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(widgetHex: colors.textPrimaryHex))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(widgetHex: colors.primaryLightHex).opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func zoneColor(raw: String) -> Color {
        switch raw {
        case "focus":
            return Color(widgetHex: colors.primaryHex)
        case "frozen":
            return Color(widgetHex: colors.accentHex)
        case "draft":
            return Color(widgetHex: colors.primaryLightHex)
        case "completed":
            return .green
        case "expired":
            return .red
        default:
            return Color(widgetHex: colors.primaryHex)
        }
    }
}

private extension Color {
    init(widgetHex: String) {
        let cleaned = widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&intValue)

        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = ((intValue >> 8) * 17, (intValue >> 4 & 0xF) * 17, (intValue & 0xF) * 17)
        case 6:
            (r, g, b) = (intValue >> 16, intValue >> 8 & 0xFF, intValue & 0xFF)
        default:
            (r, g, b) = (196, 106, 26)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
