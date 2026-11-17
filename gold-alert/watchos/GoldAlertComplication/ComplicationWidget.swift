import WidgetKit
import SwiftUI

/// 表盘复杂功能（点按即打开手表端 App，WidgetKit 复杂功能的默认行为）：
/// 圆形/矩形/行内/边角四种样式都支持。2026-11-18 ren 改定：**固定
/// 显示数字「8」**（取代构建 19–25 的铃铛图标方案；更早是价格数字
/// 方案）——复杂功能就是个打开 app 的入口，内容固定不变。
/// 构建 21 起时间线改**全静态**：内容不需要任何数据，provider 不再
/// 联网取价、policy 为 .never。原因（ren 构建 19 实测、照片实证）：
/// 原 provider 的 snapshot/timeline 都要先等 Swissquote 网络请求
/// （10 秒超时），手表端网络常完不成，WidgetKit 预算耗尽后表盘就
/// 一直显示系统占位灰条（矩形位是一条灰色横条）、真实内容画不出
/// 来。静态时间线即时完成，占位条随之消失。
struct PriceEntry: TimelineEntry {
    let date: Date
}

struct PriceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
        completion(PriceEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
        completion(Timeline(entries: [PriceEntry(date: Date())], policy: .never))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PriceEntry

    /// 固定显示数字「8」，不显示价格、不显示图标（ren 2026-11-18 定）。
    /// 字号按样式给：矩形位最大、圆形次之、边角与行内较小。
    var body: some View {
        Text("8")
            .font(.system(size: fontSize, weight: .semibold))
    }

    private var fontSize: CGFloat {
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
