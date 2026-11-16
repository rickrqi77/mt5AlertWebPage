import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    /// 这一行「到达通知价时的盈亏」（按当前模式公式算好后传入）；
    /// 算不出时为 nil，显示 --。
    let pnl: Double?
    /// 日元模式下盈亏只显示整数、不带小数（ren 2026-10-30：日元收益金额大、
    /// MT5 本身也只显示整数日元）；美元模式仍显示两位小数。
    let pnlInteger: Bool
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void

    // 注意：价格不设 @State 草稿。草稿是历次「新旧混合」的根源——行视图按位置
    // 复用时草稿残留上一份设定同位置的价格（2026-10-27 21:35 截图实证：第 5 行起
    // 逐行显示的正是旧 step3 网格在相同行号上的旧值），靠 onAppear/task/onChange
    // 同步总有行漏掉。改为直接绑定模型值：模型是什么价，画面就显示什么价，
    // 没有第二份状态可以残留。
    /// 价格字段直接读写模型：读 = item.priceText，写 = 用户编辑时回传模型。
    private var priceBinding: Binding<String> {
        Binding(get: { item.priceText }, set: { onPriceChange($0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            // 序号：只显示数字、不带句号；最多两位，固定尺寸保证显示完整不截断。
            Text("\(index + 1)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

            // 价格数字：无背景框，与背景同色（整行不要独立底色，ren 23:10 定版）。
            // 改价只靠点开编辑：整行左右滑调价已删除（ren 2026-11-17 定），
            // 左右滑改由列表层翻页（见 MainView 的 pageSwipeGesture）。
            SelectAllPriceField(text: priceBinding)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minWidth: 108, maxWidth: 108, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())

            // 盈亏数字：价格与触发按钮之间，显示两位小数，无背景框。
            // 宽度给足以原字体大小完整显示大数字（如 -12345.67），不许缩小字体。
            // 通知价一变（编辑改价写回模型），本行盈亏随画面重算同步跟着变
            //（值由 MainView 按模式公式算好传入）。
            Text(pnlText)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(pnlColor)
                .lineLimit(1)
                .padding(.vertical, 7)
                .frame(minWidth: 100, maxWidth: 100, minHeight: 36, alignment: .leading)

            Spacer(minLength: 0)

            // 触发按钮：宽一点，固定在这一行最右边、右对齐。
            Button(armTitle) { onToggleArm() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 5)
                .frame(minWidth: 74)
                .background(RoundedRectangle(cornerRadius: 8).fill(armColor))
                .foregroundStyle(armForeground)
        }
        // 每行统一的上下内边距：内容（尤其触发按钮）不再撑满整行高度，
        // 与上下分割线之间留出一致的空隙，每行间距看起来就一样了
        //（ren 2026-10-28）。行高固定约 51，MainView 侧固定行距排布。
        .padding(.vertical, 6)
        // 行底色与画面背景同色（appBackground：深色黑，浅色略压亮度的浅灰）。
        .background(Color.appBackground)
        // 行间分割线（ren 2026-10-28 要求）：每一行下方画一条线，第一行上方
        // 也画一条（最后一行下方的线就是它自己的底线）。用 overlay 画，
        // 不占布局尺寸，不影响行高实测与可视高度。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.25))
                .frame(height: 1)
        }
        .overlay(alignment: .top) {
            if index == 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(height: 1)
            }
        }
    }

    private var pnlText: String {
        guard let pnl else { return "--" }
        return pnlInteger ? String(format: "%.0f", pnl) : String(format: "%.2f", pnl)
    }

    private var pnlColor: Color {
        guard let pnl else { return .secondary }
        if pnl > 0 {
            // 正数用蓝色（系统蓝）：原深色绿/浅色蓝，ren 2026-10-28 改定统一蓝色系。
            return Color(uiColor: .systemBlue)
        }
        if pnl < 0 { return Color(red: 0.9, green: 0.4, blue: 0.35) }
        return Color.primary.opacity(0.55)
    }

    private var armTitle: String {
        if !item.enabled && item.triggered { return "已用" }
        return item.enabled ? "提醒" : "关闭"
    }

    private var armColor: Color {
        if !item.enabled && item.triggered {
            return Color.primary.opacity(0.18)
        }
        if item.enabled {
            return Color.appButton
        }
        return Color.primary.opacity(0.12)
    }

    /// 按钮文字色：绿色「提醒」底上用白字；灰底（关闭/已用）随外观用主色/次色，
    /// 保证浅色模式下也看得清。
    private var armForeground: Color {
        if item.enabled { return .white }
        if item.triggered { return .secondary }
        return .primary
    }
}
