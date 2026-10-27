import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    /// 这一行「到达通知价时的盈亏」（按当前模式公式算好后传入，显示两位小数）；
    /// 算不出时为 nil，显示 --。
    let pnl: Double?
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void

    // 注意：价格不设 @State 草稿。草稿是历次「新旧混合」的根源——行视图按位置
    // 复用时草稿残留上一份设定同位置的价格（2026-10-27 21:35 截图实证：第 5 行起
    // 逐行显示的正是旧 step3 网格在相同行号上的旧值），靠 onAppear/task/onChange
    // 同步总有行漏掉。改为直接绑定模型值：模型是什么价，画面就显示什么价，
    // 没有第二份状态可以残留。
    /// 滑动调价进度：本次拖动开始时的价格与已应用的 0.5 步数（手势驱动，
    /// 只记进度不记价格本身，价格始终以模型为准）。
    @State private var swipeStartPrice: Double?
    @State private var swipeStepsApplied = 0

    /// 价格字段直接读写模型：读 = item.priceText，写 = 用户编辑时回传模型。
    private var priceBinding: Binding<String> {
        Binding(get: { item.priceText }, set: { onPriceChange($0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            // 序号：只显示数字、不带句号；最多两位，固定尺寸保证显示完整不截断。
            Text("\(index + 1)")
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 26, alignment: .leading)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

            // 价格数字：无背景框，直接黑底（整行不要背景色，ren 23:10 定版）。
            // 在价格上左右滑动以 0.5 为单位调价（见 priceSwipeGesture）。
            SelectAllPriceField(text: priceBinding)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minWidth: 108, maxWidth: 108, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(priceSwipeGesture)

            // 盈亏数字：价格与触发按钮之间，显示两位小数，无背景框。
            // 宽度给足以原字体大小完整显示大数字（如 -12345.67），不许缩小字体。
            // 通知价一变（含滑动调价写回模型），本行盈亏随画面重算同步跟着变
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
                .padding(.vertical, 7)
                .frame(minWidth: 74)
                .background(RoundedRectangle(cornerRadius: 8).fill(armColor))
                .foregroundStyle(.white)
        }
        // 行底色就是纯黑。
        .background(Color.black)
    }

    /// 在价格上左右滑动调价（ren 2026-10-28 恢复此手势，滑动删除取消）：
    /// 横向每滑约 28pt 调整 0.5——右滑加、左滑减。拖动中即时写回模型，
    /// 价格与本行盈亏数字同步变化；只认横向滑动，纵向仍是列表滚动。
    /// 起始价在拖动开始时以模型当前价为准，避免中途被轮询刷新带偏。
    private var priceSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if swipeStartPrice == nil {
                    swipeStartPrice = item.priceValue
                    swipeStepsApplied = 0
                }
                guard let start = swipeStartPrice, start > 0 else { return }
                let steps = Int(value.translation.width / 28)
                guard steps != swipeStepsApplied else { return }
                swipeStepsApplied = steps
                let newPrice = start + Double(steps) * 0.5
                guard newPrice > 0 else { return }
                onPriceChange(String(format: "%.2f", newPrice))
            }
            .onEnded { _ in
                swipeStartPrice = nil
                swipeStepsApplied = 0
            }
    }

    private var pnlText: String {
        guard let pnl else { return "--" }
        return String(format: "%.2f", pnl)
    }

    private var pnlColor: Color {
        guard let pnl else { return Color.white.opacity(0.4) }
        if pnl > 0 { return Color(red: 0.3, green: 0.75, blue: 0.45) }
        if pnl < 0 { return Color(red: 0.9, green: 0.4, blue: 0.35) }
        return Color.white.opacity(0.55)
    }

    private var armTitle: String {
        if !item.enabled && item.triggered { return "已用" }
        return item.enabled ? "触发" : "关闭"
    }

    private var armColor: Color {
        if !item.enabled && item.triggered {
            return Color.white.opacity(0.18)
        }
        if item.enabled {
            return Color(red: 0.18, green: 0.55, blue: 0.34)
        }
        return Color.white.opacity(0.12)
    }
}
