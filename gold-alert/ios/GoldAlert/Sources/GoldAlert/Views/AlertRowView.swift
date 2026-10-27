import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void
    let onDelete: () -> Void

    // 注意：价格不设 @State 草稿。草稿是历次「新旧混合」的根源——行视图按位置
    // 复用时草稿残留上一份设定同位置的价格（2026-10-27 21:35 截图实证：第 5 行起
    // 逐行显示的正是旧 step3 网格在相同行号上的旧值），靠 onAppear/task/onChange
    // 同步总有行漏掉。改为直接绑定模型值：模型是什么价，画面就显示什么价，
    // 没有第二份状态可以残留。
    @State private var dragStepIndex = 0

    private let swipeStepWidth: CGFloat = 28

    /// 价格字段直接读写模型：读 = item.priceText，写 = 用户编辑时回传模型。
    private var priceBinding: Binding<String> {
        Binding(get: { item.priceText }, set: { onPriceChange($0) })
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 28, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            SelectAllPriceField(text: priceBinding)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 160, minHeight: 36, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))

            Button(armTitle) { onToggleArm() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(armColor))
                .foregroundStyle(.white)

            Button("删除") { onDelete() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.35))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.9, green: 0.4, blue: 0.35).opacity(0.85), lineWidth: 1)
                )
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipeAdjustGesture)
    }

    /// Left swipe −0.5, right swipe +0.5 (per ~28pt).
    private var swipeAdjustGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                // Prefer horizontal swipes.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let idx = Int((value.translation.width / swipeStepWidth).rounded(.towardZero))
                let deltaSteps = idx - dragStepIndex
                if deltaSteps != 0 {
                    nudgePrice(by: Double(deltaSteps) * 0.5)
                    dragStepIndex = idx
                }
            }
            .onEnded { _ in
                dragStepIndex = 0
            }
    }

    private func nudgePrice(by delta: Double) {
        let cleaned = item.priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = Double(cleaned) else { return }
        let next = current + delta
        let text: String
        if abs(next - next.rounded()) < 1e-9 {
            text = String(format: "%.0f", next)
        } else if abs(next * 2 - (next * 2).rounded()) < 1e-9 {
            text = String(format: "%.1f", next)
        } else {
            text = String(format: "%.2f", next)
        }
        onPriceChange(text)
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
