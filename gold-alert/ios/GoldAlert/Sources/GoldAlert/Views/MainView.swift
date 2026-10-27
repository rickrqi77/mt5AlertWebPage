import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var liquidation = LiquidationViewModel()
    @State private var confirmClear = false
    @State private var confirmSaveEmpty = false
    /// 实测的单行内容高度（不含行间隔），由前两行原点之差减去当前间隔得到。
    @State private var alertRowHeight: CGFloat = 38
    /// 提醒面板的实际高度（背景 GeometryReader 实测）：用来把行间隔按可用空间
    /// 自动拉开、填满面板下方，避免大屏（如 iPhone 17）下方空一大块。
    @State private var alertsPanelHeight: CGFloat = 0

    var body: some View {
        // 无外层滚动条：整屏紧凑排版一屏装下，提醒行多时只在面板内部滚动。
        VStack(alignment: .leading, spacing: 6) {
            header
            priceHero
            // 提醒区域在上、按钮区（间隔/保存/清除）在最底部——两者对调（ren 23:10）。
            alertsPanel
            toolbarRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 每次打开画面：自动找截图里最后一张图算最终价（找不到/图不对静默，不提示）。
        .task {
            await liquidation.autoCalculateFromLatestScreenshot()
            // 日元模式下每行盈亏数字要用美日实时汇率，打开画面时先刷一次。
            if liquidation.mode == .jpy { await liquidation.refreshUSDJPYRate() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await liquidation.autoCalculateFromLatestScreenshot()
                    if liquidation.mode == .jpy { await liquidation.refreshUSDJPYRate() }
                }
            }
        }
        // 切到日元模式时补刷一次汇率（切模式重算最终价已带回汇率时则以那次为准，
        // 这里主要兜底没有持仓数据可重算的情况）。
        .onChange(of: liquidation.mode) { _, newMode in
            if newMode == .jpy {
                Task { await liquidation.refreshUSDJPYRate() }
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
            // 点左上「提醒事项」弹出菜单：切换最终价的计算模式（日元/美元），
            // 以及实时价格来源（EA 推送价 / Swiss 报价）。两项设定都会记住，
            // 下次打开画面默认沿用。
            Menu {
                Section("最终价模式") {
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
                }
                Section("实时价格来源") {
                    ForEach(PriceSource.allCases) { source in
                        Button {
                            model.setPriceSource(source)
                        } label: {
                            if source == model.priceSource {
                                Label(source.rawValue, systemImage: "checkmark")
                            } else {
                                Text(source.rawValue)
                            }
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
            .accessibilityHint("点按切换最终价计算模式（日元/美元）与实时价格来源（EA/Swiss）")

            Spacer()
            // 右上角不放「退出」按钮（ren 21:54 要求去掉）；退出登录逻辑本身保留，
            // Token 失效时仍会自动回到解锁画面。
        }
    }

    private var priceHero: some View {
        VStack(spacing: 3) {
            // 不再单独占一行显示 XAUUSD：只剩价格行，接通状态点（绿/红）放在价格右边。
            // 价格按所选来源显示（EA 推送价或 Swiss 报价），不可点击（已取消点价格改刷新间隔的功能）。
            ZStack {
                // 实时价格只按数字本身居中（圆点不参与居中计算）：
                // Text 作为 ZStack 直接子视图被居中，圆点用 overlay 贴在数字
                // 右边缘再往右一点的位置。
                Text(format(model.displayPrice))
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(model.eaOnline
                                  ? Color(red: 0.3, green: 0.75, blue: 0.45)
                                  : Color(red: 0.9, green: 0.3, blue: 0.28))
                            .frame(width: 9, height: 9)
                            .offset(x: 22)
                            .accessibilityLabel(model.eaOnline ? "EA 在线" : "EA 离线")
                    }

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
                    .frame(maxWidth: .infinity, minHeight: 40)
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
                    .frame(maxWidth: .infinity, minHeight: 40)
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
                    .frame(maxWidth: .infinity, minHeight: 40)
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
                // 列表不做任何自动滚动：数据变化、推送完成、价格更新都不移动位置，
                // 停在哪里完全由用户自己滑动决定（ren 21:48 明确取消自动定位到当前价）。
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: effectiveRowSpacing) {
                        ForEach(Array(model.alerts.enumerated()), id: \.element.rowKey) { index, item in
                            AlertRowView(
                                index: index,
                                item: item,
                                pnl: pnl(for: item),
                                onPriceChange: { model.updatePrice(at: index, text: $0) },
                                onToggleArm: { model.toggleArm(at: index) }
                            )
                            // 行身份只能用 rowKey，绝不能用 .id(index) 按位置认行：
                            // 按位置认行时视图被复用到新设定同行号上，是新旧混合的来源。
                            .id(item.rowKey)
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
                // 不会出现最后一行只露一半。面板比 11 行紧凑高度更高时（大屏），
                // 多出的高度平摊进行间隔里（effectiveRowSpacing），下方不留空。
                .frame(height: visibleRowsHeight)
                .onPreferenceChange(RowOriginsKey.self) { origins in
                    if let y0 = origins[0], let y1 = origins[1], y1 > y0 {
                        let measured = (y1 - y0) - effectiveRowSpacing
                        if measured > 10, abs(measured - alertRowHeight) > 0.5 {
                            alertRowHeight = measured
                        }
                    }
                }
            }
        }
        .padding(10)
        // 面板占满工具栏下方的全部空间、内容顶对齐：清除到空列表时也稳稳贴在上方，
        // 不会缩成一小块浮在画面中间。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                // 提醒区域不要底色，就是背景黑（ren 23:10 定版）。
                Color.black
                // 实测面板高度，供行间隔按可用空间自动拉开（见 effectiveRowSpacing）。
                GeometryReader { geo in
                    Color.clear
                        .onAppear { alertsPanelHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newHeight in
                            alertsPanelHeight = newHeight
                        }
                }
            }
        )
    }

    /// 实际行间隔：先按紧凑值排 11 行，面板还有多余高度时把多余部分
    /// 平摊到各行之间（间隔拉大一点点、整屏铺满，下方不空），封顶 maxRowSpacing；
    /// 小屏没有多余高度时就用紧凑值。小屏/大屏（含 iPhone 17）都自适应，不写死机型。
    private var effectiveRowSpacing: CGFloat {
        let n = min(model.alerts.count, Self.maxVisibleAlertRows)
        guard n > 1, alertsPanelHeight > 0 else { return Self.minRowSpacing }
        let compact = CGFloat(n) * alertRowHeight + CGFloat(n - 1) * Self.minRowSpacing
        let available = alertsPanelHeight - Self.panelChromeHeight
        guard available > compact else { return Self.minRowSpacing }
        let spread = (available - compact) / CGFloat(n - 1)
        return min(Self.minRowSpacing + spread, Self.maxRowSpacing)
    }

    /// 列表可视高度：最多 11 行整行（n 行内容 + n−1 个实际间隔）。
    private var visibleRowsHeight: CGFloat {
        let n = min(model.alerts.count, Self.maxVisibleAlertRows)
        guard n > 0 else { return 0 }
        return CGFloat(n) * alertRowHeight + CGFloat(n - 1) * effectiveRowSpacing
    }

    /// 默认完整显示的行数，其余滑动查看。
    private static let maxVisibleAlertRows = 11
    /// 紧凑行间隔（可用空间不足时的下限，与改版前一致，保证小屏不溢出）。
    private static let minRowSpacing: CGFloat = 8
    /// 行间隔封顶，避免行数很少时被拉得太开。
    private static let maxRowSpacing: CGFloat = 24
    /// 面板里列表之外的固定占用：上下内边距 20 + 标题行约 24 + 标题与列表间隔 8。
    private static let panelChromeHeight: CGFloat = 52

    /// 收集每行在滚动区坐标系中的顶部 Y，用于实测相邻两行的行距。
    private struct RowOriginsKey: PreferenceKey {
        static let defaultValue: [Int: CGFloat] = [:]
        static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// 每行盈亏数字：价格到达这一行通知价时，持仓的实际盈亏（与 MT5 显示同号）。
    /// buy：(通知价格 − 平均价) × 合计手数 × 100；
    /// sell：方向相反，结果乘 −1（即 (平均价 − 通知价) × 合计手数 × 100）。
    /// 日元模式再除以美日实时汇率。结果显示两位小数（行内格式化）。
    /// 注：原公式 (平均价 − 通知价格) 算出的符号正好反了（2026-10-27 23:25 ren
    /// 用 MT5 截图核对：现价处应为 +465.80、原公式得 −465.80），已按实际盈亏改定。
    /// 平均价 = 所有开单价格的平均价（按手数加权，与最终价计算用的同一个平均价），
    /// 不是实时价格（ren 22:59 纠正）。平均价、合计手数、方向、汇率都来自最近一次
    /// 截图解析/最终价计算（LiquidationViewModel）。任一输入缺失（无持仓数据、
    /// 日元模式无汇率）返回 nil 显示 --；通知价一变，本函数随画面重算自动刷新。
    private func pnl(for item: AlertItem) -> Double? {
        guard let alertPrice = item.priceValue, alertPrice > 0, liquidation.averageEntry > 0 else { return nil }
        var value = (alertPrice - liquidation.averageEntry) * liquidation.totalLots * 100
        if liquidation.mode == .jpy {
            guard liquidation.usdJpyRate > 0 else { return nil }
            value /= liquidation.usdJpyRate
        }
        if liquidation.positionSide == .sell {
            value *= -1
        }
        return value
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
