import SwiftUI

/// 手表端界面分两页（ren 2026-11-15 定），竖向分页、上滑（或转表冠）翻页：
/// 第一页是时钟页——日期在上、时间在下，居中显示，尺寸适配表盘；
/// 底部中间只显示金价整数的末两位（如 4019 显示 19），字体小。
/// 三处文字共用一个亮度值（设定页滑杆 0–100 调，颜色不变、只改明暗）。
/// 第二页是间隔设定页：顶部中间连接绿点（XAU/USD、Swiss 字样已去），
/// 间隔选择、亮度进度条（原每边档数的位置；每边档数固定 7 不再
/// 可选）、最下方是价格刷新间隔选择（0.5/1/3/5/10 秒）。设定页顶部
/// 的完整价格已去掉（ren 2026-11-16 定），整页不用滚动、一页放下。
/// 没有推送按钮：点间隔即直接设定并推送；亮度停改（停下来）后
/// 自动跳回第一页看效果。无预览框、无分割线，字号与控件高度都压过。
/// 价格固定 Swiss（打开时 0.5 秒刷新、抬腕激活立刻先刷一次）；
/// 推送只是把选择发给手机执行，手机不在附近时会明确报失败。
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage = 0
    @State private var jumpBackTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedPage) {
            clockPage
                .tag(0)
            settingsPage
                .tag(1)
        }
        .tabViewStyle(.page)
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
        // 抬腕亮屏（app 回到激活态）时立刻先取一次价，不等循环节拍；
        // 放下手腕变非激活就停循环，省电也避免挂起期间的空转。
        // 回第一页也在变非激活时就做完（那时屏幕正变暗/熄灭，看不见切换），
        // 并禁用切换动画：下次亮屏直接停在第一页，没有翻页效果。
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.startAutoRefresh()
            } else {
                model.stopAutoRefresh()
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
                    .opacity(model.brightnessFraction)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(Self.secondFormatter.string(from: context.date))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .opacity(model.brightnessFraction)
                Spacer()
                Text(priceDigits)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .opacity(model.brightnessFraction)
                    .padding(.bottom, 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            brightnessSection
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

    /// 亮度控制（在原「每边档数」的位置）：调第一页日期/时间/价格
    /// 末两位共用的亮度值（调节中就实时生效于同一个状态值）。
    /// 不用系统 Slider：ren 2026-11-16 实测它的填充长度和数值对不上
    /// （85 只显示一点点）。改自绘进度条，填充宽度严格 = 数值/100，
    /// 拖动条身或转表冠都能调；停改 1.2 秒后自动跳回第一页看效果
    /// （等价于原 Slider 的松手跳回）。
    private var brightnessSection: some View {
        VStack(spacing: 2) {
            // 这几个字本身也吃同一个亮度值（ren 定）：调节时看字的
            // 明暗就能当场确认效果，不必先跳回第一页。
            Text("第一页亮度")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(model.brightnessFraction)
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.gray.opacity(0.3))
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * CGFloat(model.brightness) / 100)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let fraction = min(1, max(0, drag.location.x / geo.size.width))
                                model.brightness = (fraction * 100).rounded()
                            }
                    )
                }
                .frame(height: 16)
                .digitalCrownRotation(
                    $model.brightness,
                    from: 0,
                    through: 100,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                Text("\(Int(model.brightness))")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 26)
            }
        }
        .onChange(of: model.brightness) { _ in
            scheduleJumpBackToClock()
        }
    }

    /// 亮度停改 1.2 秒后跳回第一页；连续调节时每次变化都会顺延。
    /// 只在人还停在设定页时才跳，避免误拉正在别处操作的手。
    private func scheduleJumpBackToClock() {
        jumpBackTask?.cancel()
        jumpBackTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            if selectedPage == 1 {
                selectedPage = 0
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
