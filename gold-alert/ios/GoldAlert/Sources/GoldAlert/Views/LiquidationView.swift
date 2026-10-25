import SwiftUI

struct LiquidationView: View {
    @StateObject private var model = LiquidationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            contentBody
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .simultaneousGesture(modeSwipeGesture)
        .confirmationDialog(
            "是否删除这张截图？",
            isPresented: $model.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await model.deleteLastScreenshot() }
            }
            Button("保留", role: .cancel) {
                model.keepScreenshot()
            }
        } message: {
            Text("计算已完成。删除后相册里这张截图会移入「最近删除」。")
        }
    }

    private var headerRow: some View {
        ZStack {
            Text(model.mode.rawValue)
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.55))

            HStack {
                Text("最终价")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
        }
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await model.readLatestScreenshotAndCalculate() }
            } label: {
                Text(model.busy ? "识别中…" : "读取图片")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.23, green: 0.48, blue: 0.84))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(model.busy)

            if let err = model.errorText, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.9, green: 0.35, blue: 0.3))
            }

            if let r = model.result {
                resultCard(r)
            }
        }
    }

    /// Any horizontal swipe toggles 日元模式 ↔ 美元模式.
    private var modeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                guard abs(value.translation.width) > 40 else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleMode()
                }
            }
    }

    private func resultCard(_ r: LiquidationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("平均价", format2(r.averagePrice))
            row("手数", format(r.totalLots, digits: 2))
            row("可承受点数", format2(r.affordablePoints))
            row("最终价", format2(r.liquidationPrice), emphasize: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private func row(_ title: String, _ value: String, emphasize: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(emphasize ? .title3.weight(.bold).monospacedDigit() : .body.monospacedDigit())
                .foregroundStyle(emphasize ? Color(red: 0.83, green: 0.63, blue: 0.09) : .white)
        }
    }

    private func format2(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
