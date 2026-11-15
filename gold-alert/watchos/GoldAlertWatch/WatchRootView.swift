import SwiftUI

/// 手表端界面分两页（ren 2026-11-15 定），竖向分页、上滑（或转表冠）翻页：
/// 第一页是时钟页——日期在上、时间在下，居中显示，尺寸适配表盘；
/// 底部中间只显示金价整数的末两位（如 4019 显示 19），字体小。
/// 三处文字共用一个亮度值（设定页滑杆 0–100 调，颜色不变、只改明暗）。
/// 第二页是间隔设定页：顶部中间连接绿点（XAU/USD、Swiss 字样已去），
/// 完整价格、间隔选择、亮度滑杆（原每边档数的位置；每边档数固定 7
/// 不再可选）、推送按钮。内容已按 42mm 一页高度收紧（ren 定不要滚动）：
/// 无预览框、无分割线，间距与控件高度都压过。
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
        ScrollView {
            VStack(spacing: 5) {
                header
                priceBlock
                updatedLine
                stepPicker
                brightnessSection
                pushButton
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

    private var priceBlock: some View {
        Text(model.swissPrice > 0 ? String(format: "%.2f", model.swissPrice) : "--")
            .font(.system(size: 27, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var updatedLine: some View {
        Group {
            if let updated = model.lastUpdated {
                Text("\(updated, style: .time) 更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var stepPicker: some View {
        VStack(spacing: 4) {
            Text("间隔")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 4
            ) {
                ForEach(WatchModel.stepChoices, id: \.self) { choice in
                    chip(
                        title: WatchModel.formatStep(choice),
                        selected: model.selectedStep == choice
                    ) {
                        model.selectedStep = choice
                    }
                }
            }
        }
    }

    /// 亮度滑杆（在原「每边档数」的位置）：调第一页日期/时间/价格
    /// 末两位共用的亮度值。ren 定去掉时间日期预览框以适配一页高度，
    /// 拖动后回第一页即可看到效果。
    private var brightnessSection: some View {
        VStack(spacing: 4) {
            Text("第一页亮度")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Slider(value: $model.brightness, in: 0...100, step: 1)
                Text("\(Int(model.brightness))")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 26)
            }
        }
    }

    private var pushButton: some View {
        Button {
            model.pushSelection()
        } label: {
            HStack(spacing: 4) {
                if model.pushing {
                    ProgressView()
                }
                Text(model.pushing ? "推送中" : "设定并推送")
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
        .foregroundStyle(.white)
        .disabled(model.pushing)
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.blue : Color.gray.opacity(0.3))
        )
        .foregroundStyle(selected ? .white : .primary)
    }
}
