import WidgetKit
import SwiftUI

/// 表盘复杂功能的一条时间线条目
struct GoldEntry: TimelineEntry {
    let date: Date
    let quote: GoldQuote?
}

struct GoldProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoldEntry {
        GoldEntry(date: Date(), quote: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GoldEntry) -> Void) {
        Task {
            let q = try? await GoldFetcher.fetch()
            completion(GoldEntry(date: Date(), quote: q))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoldEntry>) -> Void) {
        Task {
            let q = try? await GoldFetcher.fetch()
            let entry = GoldEntry(date: Date(), quote: q)
            // 请求系统在 15 分钟后再次刷新。注意：watchOS 会按系统预算进一步限流，
            // 表盘上的实际刷新间隔通常 15–30 分钟，无法做到秒级实时。
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct GoldComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: GoldEntry

    private var color: Color {
        guard let q = entry.quote else { return .gray }
        return q.isUp ? .red : .green
    }
    private var price: String { entry.quote?.priceText ?? "--" }
    private var pct: String {
        guard let q = entry.quote else { return "" }
        let s = q.isUp ? "+" : ""
        return String(format: "%@%.2f%%", s, q.pct)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("AU9999 \(price) \(pct)")

        case .accessoryCorner:
            Text(price)
                .foregroundStyle(color)
                .widgetLabel("AU9999 \(pct)")

        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("AU")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(price)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("AU9999 上海金").font(.caption2).foregroundStyle(.secondary)
                Text(price).font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(pct).font(.caption2).foregroundStyle(color)
            }

        default:
            Text(price).foregroundStyle(color)
        }
    }
}

@main
struct GoldComplication: Widget {
    let kind = "GoldAU9999Complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GoldProvider()) { entry in
            // containerBackground 仅 watchOS 10+；watchOS 9 上复杂功能直接渲染即可
            if #available(watchOS 10.0, *) {
                GoldComplicationView(entry: entry)
                    .containerBackground(.clear, for: .widget)
            } else {
                GoldComplicationView(entry: entry)
            }
        }
        .configurationDisplayName("AU9999 金价")
        .description("上海金 Au99.99 实时价（系统限流，约 15–30 分钟刷新）")
        .supportedFamilies([
            .accessoryInline, .accessoryCircular,
            .accessoryRectangular, .accessoryCorner
        ])
    }
}
