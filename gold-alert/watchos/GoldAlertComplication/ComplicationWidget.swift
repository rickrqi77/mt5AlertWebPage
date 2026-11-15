import WidgetKit
import SwiftUI

/// 表盘复杂功能（点按即打开手表端 App，WidgetKit 复杂功能的默认行为）：
/// 圆形/矩形/行内/边角四种样式都支持，价格取 Swissquote 公共报价
/// （与表端 app 同源、无需凭据）。
/// 刷新节奏由系统的时间线预算决定（WidgetKit 每天约 40–75 次量级）：
/// 下面 .after(15 分钟) 只是申请，系统可以推迟，所以表盘上是分钟级
/// 快照价，2 秒/5 秒级刷新在表盘上做不到；点开 app 才是 2 秒一刷的实时价。
struct PriceEntry: TimelineEntry {
    let date: Date
    let price: Double
}

struct PriceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(date: Date(), price: 4013.8)
    }

    func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
        Self.fetchPrice { price in
            completion(PriceEntry(date: Date(), price: price))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
        Self.fetchPrice { price in
            let now = Date()
            let entry = PriceEntry(date: now, price: price)
            let next = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private static func fetchPrice(completion: @escaping (Double) -> Void) {
        guard let url = URL(string: "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD") else {
            completion(0)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var price = 0.0
            if let data = data,
               let rows = try? JSONDecoder().decode([SwissRow].self, from: data) {
                price = pickMidPrice(from: rows)
            }
            completion(price)
        }.resume()
    }

    private static func pickMidPrice(from rows: [SwissRow]) -> Double {
        var fallback = 0.0
        for row in rows {
            for profile in row.spreadProfilePrices ?? [] {
                guard let bid = profile.bid, let ask = profile.ask,
                      bid > 0, ask > 0, ask >= bid else { continue }
                let mid = ((bid + ask) / 2 * 1000).rounded() / 1000
                if fallback == 0 { fallback = mid }
                if profile.spreadProfile == "prime" { return mid }
            }
        }
        return fallback
    }
}

private struct SwissRow: Decodable {
    var spreadProfilePrices: [SwissProfile]?
}

private struct SwissProfile: Decodable {
    var spreadProfile: String?
    var bid: Double?
    var ask: Double?
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PriceEntry

    private var priceFull: String {
        entry.price > 0 ? String(format: "%.2f", entry.price) : "--"
    }

    private var priceInt: String {
        entry.price > 0 ? String(format: "%.0f", entry.price) : "--"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("XAU")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(priceInt)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("XAU/USD")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(priceFull)
                    .font(.headline)
                    .monospacedDigit()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .accessoryCorner:
            Text(priceInt)
                .font(.headline)
                .monospacedDigit()
                .widgetLabel {
                    Text("XAU/USD")
                }
        default:
            Text("XAU \(priceFull)")
                .monospacedDigit()
        }
    }
}

@main
struct GoldAlertComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoldAlertComplication", provider: PriceProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("金价")
        .description("点按打开手表端，选间隔推送到 EA。")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}
