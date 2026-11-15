import Foundation
import WatchConnectivity

/// 手表端状态与流程（ren 2026-11-15 确认的口径）：
/// - 价格固定 Swiss：打开 app 时每 0.5 秒直连 Swissquote 取一次中间价；
/// - 选择只有两项：间隔 [1, 2, 3, 4, 5, 10] 默认 5、每边档数 [3, 5, 7]
///   默认 7（上下各 7、共 15 个，与手机端一致）；
/// - 执行留在手机上：点「设定并推送」只把 {step, perSide} 经
///   WatchConnectivity 的 sendMessage 发给手机，手机用它现有的建网格逻辑
///   生成网格并 POST /api/alerts，再把结果回传到表上显示。token 不进手表。
///   手机不在附近/未连接时 sendMessage 达不到，表上明确报失败、不假装成功。
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var swissPrice: Double = 0
    @Published var selectedStep: Double = 5
    @Published var selectedPerSide: Int = 7
    @Published var phoneReachable = false
    @Published var pushing = false
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var lastUpdated: Date?

    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]
    static let perSideChoices: [Int] = [3, 5, 7]

    var totalCount: Int { selectedPerSide * 2 + 1 }

    private var refreshLoopTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    override init() {
        super.init()
        activateSession()
    }

    // MARK: - 价格（固定 Swiss，app 打开时 0.5 秒一刷）

    func refreshPrice() async {
        if let price = try? await WatchAPI.shared.fetchSwissPrice() {
            swissPrice = price
            lastUpdated = Date()
        }
    }

    func startAutoRefresh() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            await self?.refreshPrice()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }
                await self?.refreshPrice()
            }
        }
    }

    func stopAutoRefresh() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    // MARK: - 把设定发给手机执行

    func pushSelection() {
        guard WCSession.isSupported() else {
            showNotice("这只手表不支持与手机通信", isError: true)
            return
        }
        let session = WCSession.default
        phoneReachable = session.isReachable
        guard session.activationState == .activated, session.isReachable else {
            showNotice("手机不在附近或未连接，设定发不出去", isError: true)
            return
        }
        pushing = true
        let message: [String: Any] = [
            "command": "setGrid",
            "step": selectedStep,
            "perSide": selectedPerSide,
        ]
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let ok = reply["ok"] as? Bool ?? false
            let text = reply["message"] as? String ?? (ok ? "已设定" : "推送失败")
            Task { @MainActor in
                self?.pushing = false
                self?.showNotice(text, isError: !ok)
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.pushing = false
                self?.showNotice("发送失败：\(error.localizedDescription)", isError: true)
            }
        })
    }

    static func formatStep(_ step: Double) -> String {
        String(format: "%.0f", step)
    }

    private func showNotice(_ text: String, isError: Bool) {
        notice = text
        noticeIsError = isError
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            self?.notice = nil
        }
    }

    // MARK: - WatchConnectivity

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.phoneReachable = reachable
        }
    }
}
