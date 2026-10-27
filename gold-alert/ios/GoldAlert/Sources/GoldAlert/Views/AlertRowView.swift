import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    /// 这一行「到达通知价时的盈亏」（按当前模式公式算好后传入，显示两位小数）；
    /// 算不出时为 nil，显示 --。
    let pnl: Double?
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void
    let onDelete: () -> Void

    // 注意：价格不设 @State 草稿。草稿是历次「新旧混合」的根源——行视图按位置
    // 复用时草稿残留上一份设定同位置的价格（2026-10-27 21:35 截图实证：第 5 行起
    // 逐行显示的正是旧 step3 网格在相同行号上的旧值），靠 onAppear/task/onChange
    // 同步总有行漏掉。改为直接绑定模型值：模型是什么价，画面就显示什么价，
    // 没有第二份状态可以残留。
    /// 滑动删除时整行的横向偏移（手势驱动，松手未达阈值则弹回）。
    @State private var dragOffset: CGFloat = 0

    /// 价格字段直接读写模型：读 = item.priceText，写 = 用户编辑时回传模型。
    private var priceBinding: Binding<String> {
        Binding(get: { item.priceText }, set: { onPriceChange($0) })
    }

    var body: some View {
        ZStack {
            // 滑动时在行底下露出的删除区（左滑露右、右滑露左）。
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.75, green: 0.22, blue: 0.17))
                .overlay(
                    HStack {
                        if dragOffset > 8 {
                            Text("删除").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                        } else if dragOffset < -8 {
                            Spacer()
                            Text("删除").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                )
                .opacity(dragOffset == 0 ? 0 : 1)

            HStack(spacing: 6) {
                // 序号加回来（盈亏框缩窄后有空间了）：只显示数字，不带句号。
                Text("\(index + 1)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: 22, alignment: .leading)
                    .lineLimit(1)

                // 价格框：缩到正好放下数字。
                SelectAllPriceField(text: priceBinding)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: 112, maxWidth: 112, minHeight: 36, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

                // 盈亏数字：价格与触发按钮之间，显示两位小数；框缩窄到正好
                // 放下「4 位整数 + 两位小数」（如 4452.00，含负号也放得下）。
                // 通知价/平均价/手数/汇率任一变化，画面重算后立刻跟着变
                //（值由 MainView 按模式公式算好传入）。
                Text(pnlText)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pnlColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(minWidth: 94, maxWidth: 94, minHeight: 36, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

                Spacer(minLength: 0)

                // 触发按钮固定在这一行最右边、右对齐。
                Button(armTitle) { onToggleArm() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(armColor))
                    .foregroundStyle(.white)
            }
            // 行自身的不透明底色（与面板在黑底上的合成色一致），盖住底下的删除区；
            // 滑动时整行横移、删除区才露出来。
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.04)))
            .offset(x: dragOffset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipeDeleteGesture)
    }

    /// 滑动删行：横向滑过阈值（90pt，左右均可）松手就删这一行；
    /// 没滑够就弹回。替代了旧的「滑动调价 ±0.5」手势（ren 22:44 改定）。
    private var swipeDeleteGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                // 只认横向滑动；纵向是列表滚动，不动这一行。
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    if dragOffset != 0 { dragOffset = 0 }
                    return
                }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                if abs(value.translation.width) >= 90 {
                    onDelete()
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                }
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
