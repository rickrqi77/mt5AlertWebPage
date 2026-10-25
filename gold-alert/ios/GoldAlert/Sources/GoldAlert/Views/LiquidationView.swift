import SwiftUI

struct LiquidationView: View {
    @StateObject private var model = LiquidationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("爆仓价")
                    .font(.headline)
                Spacer()
                Picker("模式", selection: $model.mode) {
                    ForEach(LiquidationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            Text(model.mode == .jpy
                 ? "读取最新交易截图，只统计 GOLD（日元账户，经 USD/JPY 换算）"
                 : "读取最新交易截图，只统计 GOLD（美元账户，结余−预付款×0.2 即美元可用）")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))

            Button {
                Task { await model.readLatestScreenshotAndCalculate() }
            } label: {
                Text(model.busy ? "识别中…" : "读取图片")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.45, green: 0.32, blue: 0.75))
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

    private func resultCard(_ r: LiquidationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("模式", r.mode.rawValue)
            row("方向", r.side == .sell ? "sell" : "buy")
            row("平均价", format(r.averagePrice, digits: 5))
            row("手数", format(r.totalLots, digits: 2))
            row("爆仓价", format(r.liquidationPrice, digits: 5), emphasize: true)

            Divider().background(Color.white.opacity(0.15))

            row("结余", format(r.balance, digits: 2))
            row("预付款", format(r.margin, digits: 2))
            if let jpy = r.availableJPY {
                row("日元可用", format(jpy, digits: 4))
            }
            if let rate = r.usdJpyRate {
                row("USD/JPY", format(rate, digits: 3))
            }
            row("美元可用", format(r.availableUSD, digits: 4))
            row("可承受点数", format(r.affordablePoints, digits: 5))
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

    private func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
