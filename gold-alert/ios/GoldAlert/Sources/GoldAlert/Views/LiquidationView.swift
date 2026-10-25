import SwiftUI

struct LiquidationView: View {
    @StateObject private var model = LiquidationViewModel()
    @AppStorage("liquidationCollapsed") private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    collapsed.toggle()
                }
            } label: {
                HStack {
                    Text("最终价")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                expandedBody
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
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

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("模式", selection: $model.mode) {
                ForEach(LiquidationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(minHeight: 40)

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
