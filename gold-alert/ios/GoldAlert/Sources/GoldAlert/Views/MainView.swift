import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var confirmClear = false
    @State private var confirmSaveEmpty = false
    @State private var showPollPicker = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    priceHero
                    stepAndAutoRow
                    saveAndClearRow
                    alertsPanel
                    LiquidationView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("liquidationBottom", anchor: .bottom)
                        }
                    }
                    .id("liquidationBottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 20)
            }
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
        .confirmationDialog(
            "价格刷新间隔",
            isPresented: $showPollPicker,
            titleVisibility: .visible
        ) {
            ForEach(AppViewModel.pollChoices, id: \.self) { seconds in
                Button(Self.pollLabel(seconds)) {
                    model.setPollSeconds(seconds)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.9, green: 0.25, blue: 0.22))
                Text("提醒事项")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
            }

            Spacer()
            Button("退出") { model.logout() }
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var priceHero: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(model.quote.symbol.isEmpty ? "XAUUSD" : model.quote.symbol)
                    .font(.caption)
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09).opacity(0.85))
                Circle()
                    .fill(model.eaOnline
                          ? Color(red: 0.3, green: 0.75, blue: 0.45)
                          : Color(red: 0.9, green: 0.3, blue: 0.28))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(model.eaOnline ? "EA 在线" : "EA 离线")
            }

            ZStack {
                Button {
                    showPollPicker = true
                } label: {
                    Text(format(model.quote.price))
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityHint("点按设置价格刷新间隔")

                HStack {
                    Spacer(minLength: 0)
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Text(model.alertsPaused ? "恢复" : "暂停")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    model.alertsPaused
                                    ? Color(red: 0.18, green: 0.55, blue: 0.34)
                                    : Color.white.opacity(0.12)
                                )
                            )
                            .foregroundStyle(.white)
                    }
                    .disabled(model.busy)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Interval menu + 设定 — equal width, full row (no chevron on the menu).
    private var stepAndAutoRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AppViewModel.stepChoices, id: \.self) { value in
                    Button(String(Int(value))) {
                        model.step = value
                    }
                }
            } label: {
                Text(String(Int(model.step)))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.autoGenerate() }
            } label: {
                Text("设定")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(red: 0.23, green: 0.48, blue: 0.84))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(model.busy)
        }
    }

    /// 保存 then 清除 — equal width, full row.
    private var saveAndClearRow: some View {
        HStack(spacing: 8) {
            Button {
                if !model.alerts.isEmpty && model.armedCount == 0 {
                    confirmSaveEmpty = true
                } else {
                    Task { await model.saveAlerts() }
                }
            } label: {
                Text("保存")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(red: 0.83, green: 0.63, blue: 0.09))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(model.busy)

            Button {
                confirmClear = true
            } label: {
                Text("清除")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(red: 0.75, green: 0.22, blue: 0.17))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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

            if model.alerts.isEmpty {
                Text("暂无提醒")
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

    private func format(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        if abs(value - (value * 100).rounded() / 100) < 1e-9 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }

    private static func pollLabel(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.1f 秒", seconds)
        }
        if abs(seconds - seconds.rounded()) < 1e-9 {
            return "\(Int(seconds)) 秒"
        }
        return String(format: "%.1f 秒", seconds)
    }
}
