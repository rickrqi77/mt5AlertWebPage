import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var liquidation = LiquidationViewModel()
    @State private var confirmClear = false
    @State private var confirmSaveEmpty = false
    /// 已自动定位过的提醒列表签名（价格序列）；同一列表只自动滚一次，避免轮询/现价跳动反复抢滚动。
    @State private var scrolledSignature = ""
    /// 实测相邻两行的行距（行高+间隔），用于精确算出「正好 11 行」的列表高度。
    @State private var alertRowPitch: CGFloat = 44

    var body: some View {
        // 无外层滚动条：整屏紧凑排版一屏装下，提醒行多时只在面板内部滚动。
        VStack(alignment: .leading, spacing: 6) {
            header
            priceHero
            toolbarRow
            alertsPanel
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 每次打开画面：自动找截图里最后一张图算最终价（找不到/图不对静默，不提示）。
        .task {
            await liquidation.autoCalculateFromLatestScreenshot()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await liquidation.autoCalculateFromLatestScreenshot() }
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
    }

    private var header: some View {
        HStack {
            // 点左上「提醒事项」弹出菜单：切换最终价的计算模式（日元/美元）。
            // 模式设定后会记住，下次打开画面默认就是这个模式。
            Menu {
                ForEach(LiquidationMode.allCases) { mode in
                    Button {
                        Task { await liquidation.switchMode(mode) }
                    } label: {
                        if mode == liquidation.mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.9, green: 0.25, blue: 0.22))
                    Text("提醒事项")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("点按切换最终价计算模式（日元/美元）")

            Spacer()
            Button("退出") { model.logout() }
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var priceHero: some View {
        VStack(spacing: 3) {
            // 不再单独占一行显示 XAUUSD：只剩价格行，接通状态点（绿/红）放在价格右边。
            // 价格完全按 EA 推送显示，不可点击（已取消点价格改刷新间隔的功能）。
            ZStack {
                HStack(spacing: 8) {
                    Text(format(model.displayPrice))
                        .font(.system(size: 32, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    Circle()
                        .fill(model.eaOnline
                              ? Color(red: 0.3, green: 0.75, blue: 0.45)
                              : Color(red: 0.9, green: 0.3, blue: 0.28))
                        .frame(width: 9, height: 9)
                        .accessibilityLabel(model.eaOnline ? "EA 在线" : "EA 离线")
                }
                .frame(maxWidth: .infinity)

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

            // 最终价：不带文字标签，只显示价格本身（计算结果最后一步的值），居中，
            // 比实时价小一号。从未计算成功过显示 0；成功过则默认显示上次结果，
            // 读到新图算成功才刷新。
            Text(formatFinalPrice(liquidation.displayedLiquidationPrice))
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// 间隔下拉 + 保存 + 清除：一行三等分（已取消「设定」按钮，间隔改动即立刻重新设定）。
    private var toolbarRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(AppViewModel.stepChoices, id: \.self) { value in
                    Button(String(Int(value))) {
                        Task { await model.applyStep(value) }
                    }
                }
            } label: {
                Text(String(Int(model.step)))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.white.opacity(0.1))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                if !model.alerts.isEmpty && model.armedCount == 0 {
                    confirmSaveEmpty = true
                } else {
                    Task { await model.saveAlerts() }
                }
            } label: {
                Text("保存")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color(red: 0.83, green: 0.63, blue: 0.09))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(model.busy)

            Button {
                confirmClear = true
            } label: {
                Text("清除")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color(red: 0.75, green: 0.22, blue: 0.17))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(model.busy)
        }
    }

    private var alertsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                ScrollViewReader { rowProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: Self.alertRowSpacing) {
                            ForEach(Array(model.alerts.enumerated()), id: \.element.rowKey) { index, item in
                                AlertRowView(
                                    index: index,
                                    item: item,
                                    onPriceChange: { model.updatePrice(at: index, text: $0) },
                                    onToggleArm: { model.toggleArm(at: index) },
                                    onDelete: { model.deleteAlert(at: index) }
                                )
                                .id(index)
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
                    // 高度正好容纳 11 行整行：默认完整显示 11 个，超出的在列表内滑动，
                    // 不会出现最后一行只露一半。
                    .frame(height: visibleRowsHeight)
                    .onPreferenceChange(RowOriginsKey.self) { origins in
                        if let y0 = origins[0], let y1 = origins[1], y1 > y0 {
                            alertRowPitch = y1 - y0
                        }
                    }
                    .onAppear { scrollToNearestAlert(proxy: rowProxy) }
                    .onChange(of: model.alerts) { _, _ in scrollToNearestAlert(proxy: rowProxy) }
                    .onChange(of: model.displayPrice) { _, _ in scrollToNearestAlert(proxy: rowProxy) }
                }
            }
        }
        .padding(10)
        // 面板占满工具栏下方的全部空间、内容顶对齐：清除到空列表时也稳稳贴在上方，
        // 不会缩成一小块浮在画面中间。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    /// 通知设定刷新后，把列表停在离当前价最近的那一行附近。
    /// 只对「新的一份价格列表」定位一次：本地编辑中（alertsDirty）不抢滚动，
    /// 云端轮询带回相同价格、现价小幅跳动也不反复滚动。
    private func scrollToNearestAlert(proxy: ScrollViewProxy) {
        guard !model.alertsDirty, model.displayPrice > 0, !model.alerts.isEmpty else { return }
        let signature = model.alerts.map(\.priceText).joined(separator: "|")
        guard signature != scrolledSignature else { return }
        guard let target = nearestAlertIndex else { return }
        scrolledSignature = signature
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    /// 列表可视高度：最多 11 行整行（n 行 = n × 行距 − 1 个间隔，行距由前两行原点实测）。
    private var visibleRowsHeight: CGFloat {
        let n = min(model.alerts.count, Self.maxVisibleAlertRows)
        guard n > 0 else { return 0 }
        return CGFloat(n) * alertRowPitch - Self.alertRowSpacing
    }

    /// 默认完整显示的行数，其余滑动查看。
    private static let maxVisibleAlertRows = 11
    private static let alertRowSpacing: CGFloat = 8

    /// 收集每行在滚动区坐标系中的顶部 Y，用于实测相邻两行的行距。
    private struct RowOriginsKey: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]
        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private var nearestAlertIndex: Int? {
        let price = model.displayPrice
        guard price > 0 else { return nil }
        return model.alerts.enumerated()
            .min(by: {
                abs(($0.element.priceValue ?? .greatestFiniteMagnitude) - price)
                    < abs(($1.element.priceValue ?? .greatestFiniteMagnitude) - price)
            })?.offset
    }

    private func format(_ value: Double) -> String {
        guard value > 0 else { return "--" }
        if abs(value - (value * 100).rounded() / 100) < 1e-9 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }

    private func formatFinalPrice(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        return String(format: "%.2f", value)
    }
}
