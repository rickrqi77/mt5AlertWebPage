import SwiftUI

struct AlertRowView: View {
    let index: Int
    let item: AlertItem
    let onPriceChange: (String) -> Void
    let onToggleArm: () -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 28, alignment: .leading)

            TextField("价格", text: $draft)
                .keyboardType(.decimalPad)
                .padding(10)
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
                .font(.subheadline)
                .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.35))
        }
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
