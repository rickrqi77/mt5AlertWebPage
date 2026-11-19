import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var liquidation = LiquidationViewModel()
    @State private var confirmSaveEmpty = false
    /// 点最终价弹出的明细页（公式各项可看可改）。
    @State private var showLiquidationDetail = false
    // 注：提醒列表的显示方式几经改定：固定行距（构建 17）→ 分页
    // （构建 22–25）→ 构建 26 起改回一页内滚动：全部行排在固定区域
    // 里、超出的上下滚动看，底部按钮固定不动（ren 2026-11-18 定）。
    // 整行左右滑调价已于构建 24 删除，行上无拖动手势，滚动无争抢。

    var body: some View {
        // 无滚动：整屏紧凑排版一屏装下，提醒行分两页显示（见 alertsPanel）。
        VStack(alignment: .leading, spacing: 6) {
            header
            priceHero
            // 提醒区域在上、按钮区（间隔/保存/全设定）在最底部——两者对调（ren 23:10）。
            alertsPanel
            toolbarRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 截图解析只在打开画面、或从别处切换回 app 时各做一次：
        // 取最新截图解析；其他时候不取不解析（ren 2026-11-19 改定，
        // 持续识别已取消）。找不到/图不对静默。
        .task {
            await liquidation.autoCalculateFromLatestScreenshot()
            // 日元模式下每行盈亏数字要用美日实时汇率，打开画面时先刷一次。
            if liquidation.mode == .jpy { await liquidation.refreshUSDJPYRate() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // 回到前台：价格循环重启并立刻先取一次价刷新显示，
                // 不等间隔（ren 2026-11-19 要求，手机/手表同口径）；
                // 截图也在这时取最新一张解析一次。
                model.onAppear()
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
        .sheet(isPresented: $showLiquidationDetail) {
            LiquidationDetailView(liquidation: liquidation)
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
            // 以及实时价格来源（EA 推送价 / Swiss 报价），还有暂停/恢复提醒。两项设定都会记住，
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
                // 暂停/恢复提醒：原画面右上按钮移到这里（ren 2026-10-28）。
                Section {
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Label(
                            model.alertsPaused ? "恢复提醒" : "暂停提醒",
                            systemImage: model.alertsPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .disabled(model.busy)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.appAccentText)
                    Text("提醒事项")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.appAccentText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("点按切换最终价计算模式（日元/美元）与实时价格来源（EA/Swiss）")

            Spacer()
            // 右上角不放「退出」按钮（ren 21:54 要求去掉）；退出登录逻辑本身保留，
            // Token 失效时仍会自动回到解锁画面。
            // 右上角透明热区：单击跳转到 XAU app（ren 2026-10-31 定，
            // 当日早先是双击、同日晚改单击）。不显示任何东西；跳转走 XAU app
            // 注册的 xauusd scheme，对方没装/没注册时 openURL 回报失败、弹提示。
            Color.clear
                .frame(width: 72, height: 36)
                .contentShape(Rectangle())
                .onTapGesture { openXAUApp() }
                .accessibilityHidden(true)
        }
    }

    /// 单击主画面右上角：用 xauusd scheme 把 XAU app 拉到前台；
    /// 打不开（未安装或对方还是没注册 scheme 的旧版）时弹提示，不假装成功。
    private func openXAUApp() {
        guard let url = URL(string: "xauusd://") else { return }
        openURL(url) { accepted in
            if !accepted {
                model.showToast("打不开 XAU（未装或未更新）", error: true)
            }
        }
    }

    /// 点实时价格数字：用 metatrader5 scheme 把 MetaTrader 5 拉到前台
    /// （ren 2026-10-31 定；最终价画面改由点平均价/最终价行打开）。
    /// 打不开（未安装）时弹提示，不假装成功。
    private func openMT5App() {
        guard let url = URL(string: "metatrader5://") else { return }
        openURL(url) { accepted in
            if !accepted {
                model.showToast("打不开 MetaTrader 5（未安装）", error: true)
            }
        }
    }

    private var priceHero: some View {
        VStack(spacing: 3) {
            // 不再单独占一行显示 XAUUSD：只剩价格行，接通状态点（绿/红）放在价格右边。
            // 价格按所选来源显示（EA 推送价或 Swiss 报价）。点实时价跳转到
            // MetaTrader 5（ren 2026-10-31 改定，取代 2026-10-28 的「点实时价
            // 弹最终价画面」；最终价画面只从下方平均价/最终价行打开）。
            ZStack {
                // 实时价格只按数字本身居中（圆点不参与居中计算）：
                // Text 作为 ZStack 直接子视图被居中，圆点用 overlay 贴在数字
                // 右边缘再往右一点的位置。
                Text(format(model.displayPrice))
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                    .onTapGesture { openMT5App() }
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(model.eaOnline
                                  ? Color(red: 0.3, green: 0.75, blue: 0.45)
                                  : Color(red: 0.9, green: 0.3, blue: 0.28))
                            .frame(width: 9, height: 9)
                            .offset(x: 22)
                            .accessibilityLabel(model.eaOnline ? "EA 在线" : "EA 离线")
                    }
                // 暂停按钮已从画面去掉，改到左上角「提醒事项」菜单里（ren 2026-10-28）。
            }
            .frame(maxWidth: .infinity)

            // 平均价与最终价在同一行左右显示、中间一条竖线隔开（ren 2026-10-28）：
            // 左边平均价、右边最终价，两者同色（appAccentText 蓝；平均价两位小数，还没有持仓数据显示 --），最终价
            //（强调蓝，计算结果最后一步的值；从未计算成功过显示 0，成功过则显示
            // 上次结果，读到新图算成功才刷新）。整行可点，弹出最终价明细页
            //（ren 2026-10-31 起最终价画面只从这一行打开，实时价改跳 MT5）。
            HStack(spacing: 14) {
                Text(averagePriceText)
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.appAccentText)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: 22)
                Text(formatFinalPrice(liquidation.displayedLiquidationPrice))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.appAccentText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { showLiquidationDetail = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    /// 间隔下拉 + 保存 + 全设定：一行三等分、全部等宽（间隔改动即立刻重新设定）。
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
                    .background(Color.primary.opacity(0.1))
                    .foregroundStyle(.primary)
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
                    .background(Color.appButton)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(model.busy)

            // 「全设定」按钮（ren 2026-10-28 定）：先按现价与间隔重新计算
            // 全部通知，再除第 8 项外全部打开，并立即保存到服务器。
            Button {
                Task { await model.enableAllAlerts() }
            } label: {
                Text("全设定")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.appButton)
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
                        .foregroundStyle(.primary)
                }
                Spacer()
                // 右上角的「触发 n / 总数」计数不再显示（ren 2026-10-28 要求去掉）。
                // 分页时代（构建 22–25）这里有上一页/下一页翻页按钮，改回
                // 一页内滚动后一并去掉（ren 2026-11-18）。
            }

            if model.alerts.isEmpty {
                Text("暂无提醒")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                // 一页内滚动（ren 2026-11-18 改定，取代构建 22–25 的分页）：
                // 全部行一列排在面板的固定区域内，超出的行上下滚动看；
                // 底部按钮在面板之外、固定显示不变。构建 17–21 时滚动
                // 时灵时不灵，那时行上还挂着左右滑调价手势争抢；构建 24
                // 已把行手势删净，这次滚动不再有手势可争。滚动条隐藏
                // （2026-10-27 定版）。行高在滚动内容里按自然高度排，
                // 不存在分页时余量分摊把行拉高的问题（构建 25 的 Spacer
                // 随分页一并去掉：滚动区自己占满面板高度）。
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(allAlerts, id: \.item.rowKey) { pair in
                            AlertRowView(
                                index: pair.index,
                                item: pair.item,
                                pnl: pnl(for: pair.item),
                                pnlInteger: liquidation.mode == .jpy,
                                showsTopDivider: pair.index == 0,
                                onPriceChange: { model.updatePrice(at: pair.index, text: $0) },
                                onToggleArm: { model.toggleArm(at: pair.index) }
                            )
                            // 行身份只能用 rowKey，绝不能用 .id(index) 按位置认行：
                            // 按位置认行时视图被复用到新设定同行号上，是新旧混合的来源。
                            .id(pair.item.rowKey)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(10)
        // 面板占满工具栏下方的全部空间、内容顶对齐：清除到空列表时也稳稳贴在上方，
        // 不会缩成一小块浮在画面中间。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 提醒区域不要独立底色，与画面背景同色（appBackground）。
        .background(Color.appBackground)
    }

    /// 固定行间隔（构建 17 改定）：单行自然高约 51、间隔 8，行距约 59。
    private static let rowSpacing: CGFloat = 8

    /// 全部行（带全表下标，行内序号与操作都按全表位置）。
    private var allAlerts: [(index: Int, item: AlertItem)] {
        model.alerts.enumerated().map { ($0.offset, $0.element) }
    }

    /// 每行盈亏数字：价格到达这一行通知价时，持仓的实际盈亏（与 MT5 显示同号）。
    /// buy：(通知价格 − 平均价) × 合计手数 × 100；
    /// sell：方向相反，结果乘 −1（即 (平均价 − 通知价) × 合计手数 × 100）。
    /// 括号里算的是美元盈亏（金价以美元计、1 手 = 100 盎司）；日元模式（账户
    /// 货币是日元）下 MT5 显示的盈亏是日元，再乘以美日实时汇率换算。
    /// 2026-10-30 ren 截图实证：sell 0.05 @4019.91、现价 4011.31，美元盈亏
    /// 8.60×0.05×100 = 43.00，×157.717 = 6781.8 ≈ MT5 显示 6 781 JPY；
    /// 旧版误用除法，结果差了汇率平方倍。显示：美元模式两位小数，日元模式
    /// 只显示整数（ren 2026-10-30）。
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
            value *= liquidation.usdJpyRate
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

    /// 主画面与最终价同行的平均价：有持仓数据时四舍五入到两位小数，没有时 --。
    private var averagePriceText: String {
        guard liquidation.averageEntry > 0 else { return "--" }
        return String(format: "%.2f", liquidation.averageEntry)
    }
}
