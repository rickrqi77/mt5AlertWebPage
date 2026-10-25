import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var confirmClear = false
    @State private var confirmSaveEmpty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                priceHero
                stepPanel
                actionRow
                alertsPanel
                pauseButton
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .confirmationDialog("确定清除全部提醒？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                Task { await model.clearAll() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "没有点「触发」的价格，EA 不会提醒。仍要保存吗？",
            isPresented: $confirmSaveEmpty,
            titleVisibility: .visible
        ) {
            Button("仍要保存") {
                Task { await model.saveAlerts() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
                Text("GOLD ALERT")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
            }
            Spacer()
            Button("退出") { model.logout() }
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var priceHero: some View {
        VStack(spacing: 4) {
            Text(model.quote.symbol.isEmpty ? "XAUUSD" : model.quote.symbol)
                .font(.caption)
                .tracking(2)
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09).opacity(0.85))
            Text(model.priceLabel)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(format(model.quote.price))
                .font(.system(size: 40, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                Text("Bid \(format(model.quote.bid))")
                Text("Ask \(format(model.quote.ask))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.55))

            Text(model.eaOnline ? "EA 在线" : "EA 离线（提醒仍由 Cloudflare 下发）")
                .font(.caption2)
                .foregroundStyle(model.eaOnline
                                 ? Color(red: 0.3, green: 0.75, blue: 0.45)
                                 : Color.white.opacity(0.35))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var stepPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("间隔")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(spacing: 10) {
                Picker("间隔", selection: $model.step) {
                    ForEach(AppViewModel.stepChoices, id: \.self) { value in
                        Text(String(Int(value))).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))

                Button {
                    Task { await model.autoGenerate() }
                } label: {
                    Text("设定")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.23, green: 0.48, blue: 0.84))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(model.busy)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                confirmClear = true
            } label: {
                Text("全部清除")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.75, green: 0.22, blue: 0.17))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                if !model.alerts.isEmpty && model.armedCount == 0 {
                    confirmSaveEmpty = true
                } else {
                    Task { await model.saveAlerts() }
                }
            } label: {
                Text("保存设置")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.83, green: 0.63, blue: 0.09))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(model.busy)
        }
    }

    private var alertsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("提醒价格")
                    .font(.headline)
                Spacer()
                Text("触发 \(model.armedCount) / \(model.alerts.count)")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Text("设定后默认全部触发。不需要的点成「关闭」，再保存")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))

            if model.alerts.isEmpty {
                Text("暂无提醒，点「设定」生成后选择要触发的价格")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(model.alerts.enumerated()), id: \.element.localID) { index, item in
                    AlertRowView(
                        index: index,
                        item: item,
                        onPriceChange: { model.updatePrice(at: index, text: $0) },
                        onToggleArm: { model.toggleArm(at: index) },
                        onDelete: { model.deleteAlert(at: index) }
                    )
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private var pauseButton: some View {
        Button {
            Task { await model.togglePause() }
        } label: {
            Text(model.alertsPaused ? "恢复提醒" : "暂停提醒")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(model.alertsPaused
                              ? Color(red: 0.18, green: 0.55, blue: 0.34)
                              : Color.white.opacity(0.1))
                )
                .foregroundStyle(.white)
        }
        .disabled(model.busy)
    }

    private var footer: some View {
        Text(model.lastRefreshText)
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 20)
    }

    private func format(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        if abs(value - (value * 100).rounded() / 100) < 1e-9 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }
}
