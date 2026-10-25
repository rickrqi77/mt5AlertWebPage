import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var confirmClear = false
    @State private var confirmSaveEmpty = false
    @State private var showPollPicker = false
    @State private var alertRowPitch: CGFloat = 52

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 第 1 屏：顶部 + 提醒价格（恰好 9 行）。底部用弹性留白填满整屏，
                        // 让“最终价”区域完全落在第 2 屏，首屏不露出。
                        VStack(alignment: .leading, spacing: 8) {
                            header
                            priceHero
                            stepAndAutoRow
                            saveAndClearRow
                            alertsPanel
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)

                        // 第 2 屏：最终价（紧贴提醒面板下方）
                        LiquidationView {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo("liquidationBottom", anchor: .bottom)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                        .id("liquidationBottom")
                    }
                }
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
        VStack(spacing: 4) {
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
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
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
        .padding(.vertical, 4)
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
                    .frame(maxWidth: .infinity, minHeight: 38)
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
                    .frame(maxWidth: .infinity, minHeight: 38)
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
                    .frame(maxWidth: .infinity, minHeight: 38)
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
                    .frame(maxWidth: .infinity, minHeight: 38)
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
                if model.doneFlash {
                    Text("  完成")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
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
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: Self.alertRowSpacing) {
                        ForEach(Array(model.alerts.enumerated()), id: \.element.localID) { index, item in
                            AlertRowView(
                                index: index,
                                item: item,
                                onPriceChange: { model.updatePrice(at: index, text: $0) },
                                onToggleArm: { model.toggleArm(at: index) },
                                onDelete: { model.deleteAlert(at: index) }
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: RowOriginsKey.self,
                                        value: [index: geo.frame(in: .named("alertRows")).minY]
                                    )
                                }
                            )
                        }
                    }
                }
                .coordinateSpace(name: "alertRows")
                .frame(height: visibleRowsHeight)
                .onPreferenceChange(RowOriginsKey.self) { origins in
                    if let y0 = origins[0], let y1 = origins[1], y1 > y0 {
                        alertRowPitch = y1 - y0
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    /// Height of the alert rows region, capped so exactly 9 rows show; extras scroll inside.
    /// n 行内容高度 = n × 行间距(pitch) − 1 个间距（由前两行原点实测，精确到像素）。
    private var visibleRowsHeight: CGFloat {
        let n = min(model.alerts.count, 9)
        guard n > 0 else { return 0 }
        return CGFloat(n) * alertRowPitch - Self.alertRowSpacing
    }

    /// 收集每行在滚动区坐标系中的顶部 Y，用于实测相邻两行的行间距。
    private struct RowOriginsKey: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]
        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private static let alertRowSpacing: CGFloat = 10

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
