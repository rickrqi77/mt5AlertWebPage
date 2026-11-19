import SwiftUI

/// 手表端界面分三页，竖向分页、上滑（或转表冠）翻页
///（第三页一键全平为 2026-11-18 新增，前两页维持 ren 2026-11-15 定版）：
/// 第一页是时钟页——日期在上、时间在下，居中显示，尺寸适配表盘；
/// 底部中间只显示金价整数的末两位（如 4019 显示 19），字号 20
///（原 15，ren 2026-11-17 要求加大一点）。
/// 时钟页文字不做 app 内亮度调节，直接用手表系统亮度显示。
/// 第二页是间隔设定页（ren 2026-11-20 改版）：连接绿点在左上角，
/// 「间隔」标题靠左、按钮加高，中间一条分割线，下方是刷新间隔
/// 两排六档（0.5/1/2、3/5/10 秒），整页正好撑满一屏、不用滚动。
/// 设定页顶部的完整价格已去掉（ren 2026-11-16 定）。
/// 亮度调节已删（ren 2026-11-20 定）：app 不再自定义亮度，
/// 时钟页文字直接按手表系统亮度显示。
/// 没有推送按钮：点间隔即直接设定——有服务器凭据时直发后台
/// （手机没打开也能生效），无凭据时回退经手机发送。
/// 价格固定 Swiss（打开/抬腕激活立刻先刷一次，之后按刷新间隔）。
/// 第三页平仓页右下角空白区双击回第一页（ren 2026-11-20 要求）。
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage = 0

    var body: some View {
        TabView(selection: $selectedPage) {
            clockPage
                .tag(0)
            settingsPage
                .tag(1)
            closeAllPage
                .tag(2)
        }
        .tabViewStyle(.page)
        .onAppear {
            // 打开先直接取一次 Swiss 价刷新显示，不等循环节拍
            // （ren 2026-11-19 要求，手机/手表同口径）；循环本身
            // 也是先取后等，这里再直调一次保底激活瞬间不被推迟。
            Task { await model.refreshPrice() }
            model.startAutoRefresh()
        }
        .onDisappear { model.stopAutoRefresh() }
        // 抬腕亮屏（app 回到激活态）时立刻先取一次价，不等循环节拍；
        // 退到后台（手腕放下、屏幕熄灭）就停循环并回第一页（禁用
        // 切换动画，下次亮屏直接停在第一页）。注意只认 .background：
        // .inactive 只是临时打断（通知横幅、亮屏过渡），旧版在
        // .inactive 就打回第一页+清平仓确认态，ren 在平仓页操作中
        // 被打回首页（2026-11-20 报），故改定只在真正退后台时回。
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await model.refreshPrice() }
                model.startAutoRefresh()
            } else if phase == .background {
                model.stopAutoRefresh()
                model.closeAllPageReset()
                resetToClockPage()
            }
        }
    }

    /// 无动画地切回第一页（时钟页）。
    private func resetToClockPage() {
        guard selectedPage != 0 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedPage = 0
        }
    }

    // MARK: - 第一页：时钟页

    private var clockPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Spacer()
                Text(Self.dateFormatter.string(from: context.date))
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(Self.secondFormatter.string(from: context.date))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(priceDigits)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 右下角热区：双击直接跳第三页平仓画面（ren 2026-11-18 定）。
        // 热区透明、无单击动作，不影响时钟页任何显示与手势。
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 90, height: 70)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    selectedPage = 2
                }
        }
    }

    /// 金价整数部分的末两位（4019.x → "19"，4005.x → "05"）；还没取到价显示 "--"。
    private var priceDigits: String {
        guard model.swissPrice > 0 else { return "--" }
        return String(format: "%02d", Int(model.swissPrice) % 100)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let secondFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ss"
        return f
    }()

    // MARK: - 第二页：间隔设定页

    /// 设定页布局（ren 2026-11-20 改版）：连接圆点在左上角、内容
    /// 整体上移；「间隔」标题靠左；间隔区与刷新间隔区之间一条
    /// 分割线；刷新间隔两排六档（0.5/1/2、3/5/10）。按钮高度
    /// 初版 38/34 太高、整页溢出把顶部标题和底部都挤出屏外
    /// （ren 装机构图实报），改 30/28 并收紧间距，整页留出余量。
    private var settingsPage: some View {
        VStack(spacing: 4) {
            header
            stepPicker
            Divider()
            refreshPicker
            if !model.hasServerCredentials {
                Text("未同步直发凭据，暂经手机发送")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(model.noticeIsError ? .red : .green)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// 连接状态点（绿=手机可达、灰=不可达）固定在屏幕左上角；
    /// ren 定 XAU/USD 与 Swiss 字样都不要。
    private var header: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.phoneReachable ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Spacer()
        }
    }

    private var stepPicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("间隔")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 3
            ) {
                ForEach(WatchModel.stepChoices, id: \.self) { choice in
                    chip(
                        title: WatchModel.formatStep(choice),
                        selected: model.selectedStep == choice,
                        height: 30
                    ) {
                        // 点间隔 = 直接设定（ren 定不要按钮）：有凭据
                        // 直发服务器、无凭据回退经手机（见 WatchModel）。
                        model.selectedStep = choice
                        model.applyStepSelection()
                    }
                }
            }
        }
    }

    /// 分割线下方：实时价格刷新间隔（单位秒，标题不带单位），
    /// 两排六档：0.5/1/2、3/5/10。
    private var refreshPicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("刷新间隔")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 3
            ) {
                ForEach(WatchModel.refreshChoices, id: \.self) { choice in
                    chip(
                        title: WatchModel.formatInterval(choice),
                        selected: model.refreshInterval == choice,
                        fontSize: 14,
                        height: 28
                    ) {
                        model.refreshInterval = choice
                    }
                }
            }
        }
    }

    // MARK: - 第三页：一键全平

    /// 一键全平单独一页（不挤设定页）：点「全部平仓」只进确认态、
    /// 不取任何数据；点「确认全平」即把指令发给手机、立刻显示
    /// 已发送，不等结果（ren 2026-11-18 改定）。放下手腕会把
    /// 确认/结果态收回待机。
    private var closeAllPage: some View {
        VStack(spacing: 8) {
            Text("一键全平")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch model.closeAllPhase {
            case .idle:
                closeAllButton(title: "全部平仓", enabled: true) {
                    model.closeAllAskConfirm()
                }
                Text("平掉账户全部持仓")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .confirm:
                Text("确认平掉全部持仓？")
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                closeAllButton(title: "确认全平", enabled: true) {
                    model.closeAllConfirm()
                }
                Button("取消") { model.closeAllCancel() }
                    .font(.caption)
            case .result(let text, let isError):
                Text(text)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .green)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        // 右下角空白区双击回第一页（ren 2026-11-20 要求）：与第一页
        // 的双击进平仓页对称；离开时顺手把确认/结果态收回待机。
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 90, height: 70)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.closeAllPageReset()
                    selectedPage = 0
                }
        }
    }

    private func closeAllButton(
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(enabled ? 1 : 0.4))
        )
        .foregroundStyle(.white)
        .disabled(!enabled)
    }

    private func chip(
        title: String,
        selected: Bool,
        fontSize: CGFloat = 15,
        height: CGFloat = 26,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.blue : Color.gray.opacity(0.3))
        )
        .foregroundStyle(selected ? .white : .primary)
    }
}
