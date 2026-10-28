import SwiftUI

/// 最终价明细页（点主画面最终价弹出，ren 2026-10-28 要求）：
/// 把最终价计算公式的项目与当前值全部列出；输入项（结余/预付款/平均价/
/// 合计手数/方向，日元模式另有汇率）可手工修改，下方计算过程与最终价
/// 随改动实时重算；点「保存」后按新值正式重算并存为当前持仓数据
///（主画面最终价、每行盈亏的平均价/手数/方向都随之更新）。
struct LiquidationDetailView: View {
    @ObservedObject var liquidation: LiquidationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var balanceText = ""
    @State private var marginText = ""
    @State private var averageText = ""
    @State private var lotsText = ""
    @State private var rateText = ""
    @State private var side: PositionSide = .buy
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("计算项目（可修改）") {
                    editRow("结余", $balanceText)
                    editRow("预付款", $marginText)
                    editRow("平均价", $averageText)
                    editRow("合计手数", $lotsText)
                    HStack {
                        Text("方向")
                        Spacer()
                        Picker("方向", selection: $side) {
                            Text("买入 buy").tag(PositionSide.buy)
                            Text("卖出 sell").tag(PositionSide.sell)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    if liquidation.mode == .jpy {
                        editRow("美日汇率", $rateText)
                    }
                }

                Section("计算过程") {
                    if let preview {
                        if liquidation.mode == .jpy, let availableJPY = preview.availableJPY {
                            readRow("可用资金（日元）", "结余 − 预付款 × 0.2", fmt(availableJPY))
                            readRow("可用资金（美元）", "可用资金（日元）÷ 汇率", fmt(preview.availableUSD))
                        } else {
                            readRow("可用资金", "结余 − 预付款 × 0.2", fmt(preview.availableUSD))
                        }
                        readRow("可承受点数", "可用资金 ÷ (合计手数 × 100)", fmt(preview.affordablePoints))
                        readRow(
                            "最终价",
                            side == .buy ? "平均价 − 可承受点数" : "平均价 + 可承受点数",
                            fmt(preview.liquidationPrice)
                        )
                    } else {
                        Text("请填入有效的结余、预付款、平均价与合计手数（日元模式还需汇率）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let preview {
                    Section {
                        Text(fmt(preview.liquidationPrice))
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.appAccentText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } header: {
                        Text("最终价（\(liquidation.mode.rawValue)）")
                    }
                }
            }
            .navigationTitle("最终价计算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(preview == nil)
                }
            }
            .onAppear { loadDraft() }
        }
    }

    // MARK: - Rows

    private func editRow(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 130)
        }
    }

    private func readRow(_ title: String, _ formula: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(formula)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }

    // MARK: - Draft & preview

    /// 草稿拼成的持仓数据：一笔合成持仓（方向/手数/开仓价 = 方向/合计手数/平均价），
    /// 与截图解析出的数据走完全相同的计算器，保证预览与正式保存结果一致。
    private var draftData: ScreenshotTradeData? {
        guard let balance = Double(balanceText),
              let margin = Double(marginText),
              let average = Double(averageText),
              let lots = Double(lotsText),
              average > 0, lots > 0 else { return nil }
        return ScreenshotTradeData(
            balance: balance,
            margin: margin,
            positions: [GoldPosition(symbol: "GOLD", side: side, lots: lots, entryPrice: average)]
        )
    }

    private var preview: LiquidationResult? {
        guard let data = draftData else { return nil }
        switch liquidation.mode {
        case .usd:
            return try? LiquidationCalculator.calculateUSD(data: data)
        case .jpy:
            guard let rate = Double(rateText), rate > 0 else { return nil }
            return try? LiquidationCalculator.calculateJPY(data: data, usdJpyRate: rate)
        }
    }

    private func loadDraft() {
        guard !loaded else { return }
        loaded = true
        let inputs = liquidation.currentInputs
        balanceText = inputText(inputs.balance)
        marginText = inputText(inputs.margin)
        // 平均价与合计手数四舍五入到两位小数再显示（ren 2026-10-28 要求平均价；
        // 手数同理，避免 4030.4999… / 0.1500000002 这类长尾小数挤满输入框）。
        averageText = roundedText(inputs.averageEntry)
        lotsText = roundedText(inputs.totalLots)
        side = inputs.side ?? .buy
        if liquidation.usdJpyRate > 0 {
            rateText = inputText(liquidation.usdJpyRate)
        }
    }

    private func save() {
        guard let data = draftData, preview != nil,
              let position = data.positions.first else { return }
        let rate = liquidation.mode == .jpy ? Double(rateText) : nil
        Task {
            await liquidation.applyManualInputs(
                balance: data.balance,
                margin: data.margin,
                averageEntry: position.entryPrice,
                totalLots: position.lots,
                side: position.side,
                usdJpyRate: rate
            )
            dismiss()
        }
    }

    // MARK: - Formatting

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// 两位小数写法：0 显示为空，其余四舍五入到两位小数（如 4030.68）。
    private func roundedText(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return String(format: "%.2f", value)
    }

    /// 输入框初始值：0 显示为空（方便直接输入），其余用最短精确写法（如 4012.93）。
    private func inputText(_ value: Double) -> String {
        guard value != 0 else { return "" }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
