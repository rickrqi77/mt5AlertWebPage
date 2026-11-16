import WidgetKit
import SwiftUI

/// 表盘复杂功能（点按即打开手表端 App，WidgetKit 复杂功能的默认行为）：
/// 圆形/矩形/行内/边角四种样式都支持。2026-11-17 ren 改定：**只显示
/// 铃铛图标、不显示任何价格数字**（取代原圆形末两位/矩形完整价/边角
/// 整数价的数字方案）——复杂功能就是个打开 app 的按钮，价格进 app
/// 看实时。
/// 构建 21 起时间线改**全静态**：图标不需要任何数据，provider 不再
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
