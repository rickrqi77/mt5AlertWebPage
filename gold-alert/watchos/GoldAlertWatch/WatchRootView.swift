import SwiftUI

/// 手表端主界面，按 Apple Watch Series 12 的 42mm 表壳（187×223pt）优先排版：
/// 价格大字一行放得下、间隔选项 3 列小格、推送按钮整行；内容约两屏高，
/// 表冠滚动看完。46mm 上同一套布局自动放宽，不另做一套。
struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                header
                priceBlock
                statusLine
                Divider()
                stepPicker
                pushButton
                if !model.hasCredentials {
                    Text("先在 iPhone 上打开提醒事项解锁一次，凭据会自动同步到手表。现在显示的是 Swiss 报价。")
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
                refreshButton
            }
            .padding(.horizontal, 4)
        }
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.eaOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text("XAU/USD")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if !model.priceSourceText.isEmpty {
                Text(model.priceSourceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var priceBlock: some View {
        Text(model.displayPrice > 0 ? String(format: "%.2f", model.displayPrice) : "--")
            .font(.system(size: 29, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var statusLine: some View {
        VStack(spacing: 1) {
            if model.serverStep > 0 {
                Text("现间隔 \(WatchModel.formatStep(model.serverStep)) · 已开 \(model.armedCount)/\(model.totalCount) 个")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let updated = model.lastUpdated {
                Text("\(updated, style: .time) 更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var stepPicker: some View {
        VStack(spacing: 5) {
            Text("间隔设定（上下各 7 个）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 5
            ) {
                ForEach(WatchModel.stepChoices, id: \.self) { choice in
                    Button {
                        model.selectedStep = choice
                    } label: {
                        Text(WatchModel.formatStep(choice))
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(model.selectedStep == choice ? Color.blue : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(model.selectedStep == choice ? .white : .primary)
                }
            }
        }
    }

    private var pushButton: some View {
        Button {
            Task { await model.pushSelectedStep() }
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
        .disabled(model.pushing || !model.hasCredentials || model.displayPrice <= 0)
        .opacity(model.hasCredentials ? 1 : 0.45)
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Label("刷新", systemImage: "arrow.clockwise")
                .font(.caption)
        }
        .disabled(model.busy)
    }
}
