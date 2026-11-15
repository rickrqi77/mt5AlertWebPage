import SwiftUI

/// 手表端主界面，按 Apple Watch Series 12 的 42mm 表壳（187×223pt）优先排版：
/// 价格大字一行、间隔 3 列小格、每边档数一行 3 格、推送按钮整行；
/// 内容约两屏高，表冠滚动看完。46mm 上同一套布局自动放宽。
/// 价格固定 Swiss（打开时 1 秒刷新、抬腕激活立刻先刷一次）；推送只是把选择发给手机执行，
/// 手机不在附近时按钮点了会明确报失败。
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                header
                priceBlock
                updatedLine
                Divider()
                stepPicker
                perSidePicker
                summaryLine
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
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
        // 抬腕亮屏（app 回到激活态）时立刻先取一次价，不等循环节拍；
        // 放下手腕变非激活就停循环，省电也避免挂起期间的空转。
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.startAutoRefresh()
            } else {
                model.stopAutoRefresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.phoneReachable ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text("XAU/USD")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Swiss")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var priceBlock: some View {
        Text(model.swissPrice > 0 ? String(format: "%.2f", model.swissPrice) : "--")
            .font(.system(size: 29, weight: .bold, design: .rounded))
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
        VStack(spacing: 5) {
            Text("间隔")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 5
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

    private var perSidePicker: some View {
        VStack(spacing: 5) {
            Text("每边档数")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(WatchModel.perSideChoices, id: \.self) { choice in
                    chip(
                        title: "\(choice)",
                        selected: model.selectedPerSide == choice
                    ) {
                        model.selectedPerSide = choice
                    }
                }
            }
        }
    }

    private var summaryLine: some View {
        Text("上下各 \(model.selectedPerSide) 档 · 共 \(model.totalCount) 个")
            .font(.caption2)
            .foregroundStyle(.secondary)
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
            .frame(maxWidth: .infinity, minHeight: 36)
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
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.blue : Color.gray.opacity(0.3))
        )
        .foregroundStyle(selected ? .white : .primary)
    }
}
