import WidgetKit
import SwiftUI

/// 表盘复杂功能（点按即打开手表端 App，WidgetKit 复杂功能的默认行为）：
/// 圆形/矩形/行内/边角四种样式都支持。2026-11-17 ren 改定：**只显示
/// 铃铛图标、不显示任何价格数字**（取代原圆形末两位/矩形完整价/边角
/// 整数价的数字方案）——复杂功能就是个打开 app 的按钮，价格进 app
/// 看实时。价格时间线保留不删（provider 结构不动，日后想恢复数字
/// 只需改 ComplicationView），当前视图不使用 entry.price。
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

    /// 只显示铃铛图标（与手机端标题同一个铃铛），不显示数字
    /// （ren 2026-11-17 定）。字号按样式给：矩形位最大、圆形次之、
    /// 边角与行内较小。
    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: iconSize, weight: .semibold))
    }

    private var iconSize: CGFloat {
        switch family {
        case .accessoryRectangular: return 30
        case .accessoryCircular: return 22
        case .accessoryCorner: return 19
        default: return 16
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
