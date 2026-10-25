import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""
    @State private var dragStepIndex = 0

    private let swipeStepWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 36, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            SelectAllPriceField(text: $draft)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .onAppear { draft = item.priceText }
            .onChange(of: item.priceText) { _, newValue in
                if draft != newValue { draft = newValue }
            }
            .onChange(of: draft) { _, newValue in
                onPriceChange(newValue)
            }

            Button(armTitle) { onToggleArm() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(armColor))
                .foregroundStyle(.white)

            Button("删除") { onDelete() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
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
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
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
        draft = text
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
