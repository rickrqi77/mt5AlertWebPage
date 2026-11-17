import Foundation
import WatchConnectivity

/// 手表端状态与流程（ren 2026-11-15 确认的口径）：
/// - 价格固定 Swiss：打开 app 时直连 Swissquote 取中间价，刷新间隔
///   可在设定页选 0.5 / 1 / 3 / 5 / 10 秒（默认 0.5）；
/// - 选择只有一项：间隔 [1, 2, 3, 4, 5, 10] 默认 5；每边档数固定 7
///   （上下各 7、共 15 个，与手机端一致，表上不再提供选择）；
/// - 第一页（时钟页）的日期/时间/价格末两位共用一个亮度值（0–100，
///   默认 100），在设定页用滑杆调、存 UserDefaults；
/// - 执行留在手机上：在表上点间隔即把 {step, perSide} 经
///   WatchConnectivity 的 sendMessage 发给手机（无确认按钮），手机用它现有的建网格逻辑
///   生成网格并 POST /api/alerts，再把结果回传到表上显示。token 不进手表。
///   手机不在附近/未连接时 sendMessage 达不到，表上明确报失败、不假装成功。
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var swissPrice: Double = 0
    @Published var selectedStep: Double = 5
    @Published var phoneReachable = false
    @Published var pushing = false
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var lastUpdated: Date?

    /// 第一页亮度（0–100），日期/时间/价格末两位统一用这一个值。
    @Published var brightness: Double = 100 {
        didSet { UserDefaults.standard.set(brightness, forKey: Self.brightnessKey) }
    }
    private static let brightnessKey = "clockBrightness"
    var brightnessFraction: Double { brightness / 100 }

    /// 实时价格刷新间隔（秒），设定页可选；循环每轮读当前值，改完
    /// 下一轮即生效。实际周期 = 请求耗时 + 此间隔。
    @Published var refreshInterval: Double = 0.5 {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey) }
    }
    private static let refreshIntervalKey = "refreshInterval"
    static let refreshChoices: [Double] = [0.5, 1, 3, 5, 10]

    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]
    /// 每边档数固定 7（ren 定：表上不提供选择，与手机一致）。
    static let perSide = 7

    private var refreshLoopTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    override init() {
        super.init()
        if let saved = UserDefaults.standard.object(forKey: Self.brightnessKey) as? Double {
            brightness = min(100, max(0, saved))
        }
        if let saved = UserDefaults.standard.object(forKey: Self.refreshIntervalKey) as? Double,
           Self.refreshChoices.contains(saved) {
            refreshInterval = saved
        }
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
                let interval = self?.refreshInterval ?? 0.5
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
        // 点间隔直接触发推送（无按钮）；推送进行中再点不重复发。
        guard !pushing else { return }
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
            "perSide": Self.perSide,
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

    // MARK: - 一键全平（第三页）

    /// ren 2026-11-18 改定为即发即走：不向手机取数（不查持仓数、
    /// 不等 EA 结果），点确认即把指令发给手机、立刻显示已发送。
    enum CloseAllPhase {
        case idle
        case confirm
        case result(text: String, isError: Bool)
    }

    @Published var closeAllPhase: CloseAllPhase = .idle
    private var closeAllResetTask: Task<Void, Never>?

    /// 点「全部平仓」：只进确认态，不发任何请求。
    func closeAllAskConfirm() {
        closeAllPhase = .confirm
    }

    func closeAllCancel() {
        closeAllPhase = .idle
    }

    /// 点「确认全平」：把指令发给手机就完事，不等回话、不等结果。
    /// 只有手机当下不可达才报错（指令根本没出门）。
    func closeAllConfirm() {
        guard let session = reachableSession() else {
            closeAllPhase = .result(text: "手机不在附近或未连接", isError: true)
            scheduleCloseAllReset()
            return
        }
        session.sendMessage(
            ["command": "closeAll"],
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
        closeAllPhase = .result(text: "平仓指令已发送", isError: false)
        scheduleCloseAllReset()
    }

    /// 放下手腕时把确认/结果态收回待机（发送中、准备中不打断，等回复落定）。
    func closeAllPageReset() {
        switch closeAllPhase {
        case .confirm, .result:
            closeAllResetTask?.cancel()
            closeAllPhase = .idle
        default:
            break
        }
    }

    private func reachableSession() -> WCSession? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        phoneReachable = session.isReachable
        guard session.activationState == .activated, session.isReachable else { return nil }
        return session
    }

    /// 结果态停留约 3 秒后自动回待机态。
    private func scheduleCloseAllReset() {
        closeAllResetTask?.cancel()
        closeAllResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            if let phase = self?.closeAllPhase, case .result = phase {
                self?.closeAllPhase = .idle
            }
        }
    }

    static func formatStep(_ step: Double) -> String {
        String(format: "%.0f", step)
    }

    static func formatInterval(_ value: Double) -> String {
        value < 1 ? String(format: "%.1f", value) : String(format: "%.0f", value)
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
