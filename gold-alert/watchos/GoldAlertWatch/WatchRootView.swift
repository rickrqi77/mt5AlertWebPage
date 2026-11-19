import SwiftUI

/// 手表端界面分三页，竖向分页、上滑（或转表冠）翻页
///（第三页一键全平为 2026-11-18 新增，前两页维持 ren 2026-11-15 定版）：
/// 第一页是时钟页——日期在上、时间在下，居中显示，尺寸适配表盘；
/// 底部中间只显示金价整数的末两位（如 4019 显示 19），字号 20
///（原 15，ren 2026-11-17 要求加大一点）。
/// 时钟页文字不做 app 内亮度调节，直接用手表系统亮度显示。
/// 第二页是间隔设定页：顶部中间连接绿点（XAU/USD、Swiss 字样已去），
/// 间隔选择、最下方是价格刷新间隔选择（0.5/1/3/5/10 秒）。设定页顶部
/// 的完整价格已去掉（ren 2026-11-16 定），整页不用滚动、一页放下。
/// 亮度调节已删（ren 2026-11-20 定）：app 不再自定义亮度，
/// 时钟页文字直接按手表系统亮度显示。
/// 没有推送按钮：点间隔即直接设定并推送；亮度停改（停下来）后
/// 自动跳回第一页看效果。无预览框、无分割线，字号与控件高度都压过。
/// 价格固定 Swiss（打开时 0.5 秒刷新、抬腕激活立刻先刷一次）；
/// 推送只是把选择发给手机执行，手机不在附近时会明确报失败。
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

    private var settingsPage: some View {
        VStack(spacing: 3) {
            header
            stepPicker
            refreshPicker
            if !model.phoneReachable {
                Text("推送需要手机在附近并保持连接")
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
        .padding(.horizontal, 4)
    }

    /// 顶部只留连接状态点（绿=手机可达、灰=不可达），横向居中；
    /// ren 定 XAU/USD 与 Swiss 字样都不要。
    private var header: some View {
        HStack(spacing: 4) {
            Spacer()
            Circle()
                .fill(model.phoneReachable ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Spacer()
        }
    }

    private var stepPicker: some View {
        VStack(spacing: 3) {
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
                        selected: model.selectedStep == choice
                    ) {
                        // 点间隔 = 直接设定并推送（ren 定不要按钮）。
                        model.selectedStep = choice
                        model.pushSelection()
                    }
                }
            }
        }
    }

    /// 设定页最下方：实时价格刷新间隔（单位秒，标题不带单位），五个一排。
    private var refreshPicker: some View {
        VStack(spacing: 2) {
            Text("刷新间隔")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                ForEach(WatchModel.refreshChoices, id: \.self) { choice in
                    chip(
                        title: WatchModel.formatInterval(choice),
                        selected: model.refreshInterval == choice,
                        fontSize: 13,
                        height: 26
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
        .padding(.horizontal, 6)
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
