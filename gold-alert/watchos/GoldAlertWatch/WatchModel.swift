import Foundation
import WatchConnectivity

/// 手表端状态与流程（ren 2026-11-15 确认的口径）：
/// - 价格固定 Swiss：打开 app 时直连 Swissquote 取中间价，刷新间隔
///   在设定页用步进器在 0.5 / 1 / 2 / 5 / 10 秒间循环切换（默认 0.5）；
/// - 选择只有一项：间隔 [1, 2, 3, 4, 5, 10] 默认 5；每边档数固定 7
///   （上下各 7、共 15 个，与手机端一致，表上不再提供选择）；
/// - 亮度不做 app 内调节（ren 2026-11-20 定）：直接用手表系统亮度；
/// - 设定执行（ren 2026-11-20 改定）：表上点间隔直接把网格 POST 到
///   服务器 /api/alerts（用表上现取的 Swiss 价建网格，规则与手机
///   buildGrid 一致），不经手机中转——手机 app 没打开也能生效，
///   EA 下个同步周期即采用。凭据（服务器地址+token）由手机解锁后
///   经 applicationContext 同步到手表、存 Keychain；还没同步到时
///   回退旧通道：sendMessage 发给手机执行（手机不可达时
///   transferUserInfo 排队），sendMessage 有 12 秒回话看门狗。
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var swissPrice: Double = 0
    @Published var selectedStep: Double = 5
    @Published var phoneReachable = false
    @Published var pushing = false
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var lastUpdated: Date?

    /// 实时价格刷新间隔（秒），设定页可选；循环每轮读当前值，改完
    /// 下一轮即生效。实际周期 = 请求耗时 + 此间隔。
    @Published var refreshInterval: Double = 0.5 {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey) }
    }
    private static let refreshIntervalKey = "refreshInterval"
    static let refreshChoices: [Double] = [0.5, 1, 2, 5, 10]

    /// 刷新间隔步进（ren 2026-11-20 改定）：设定页改成 − 值 + 的
    /// 步进器，在 [0.5, 1, 2, 5, 10] 之间循环切换（加号往大、
    /// 减号往小，到头绕回另一端）。
    func cycleRefreshInterval(increase: Bool) {
        let choices = Self.refreshChoices
        guard let idx = choices.firstIndex(of: refreshInterval) else {
            refreshInterval = choices[0]
            return
        }
        let next = increase
            ? (idx + 1) % choices.count
            : (idx - 1 + choices.count) % choices.count
        refreshInterval = choices[next]
    }

    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]

    /// 服务器凭据（手机同步过来、存 Keychain）：设定直发服务器用。
    @Published private(set) var apiBaseURL: String?
    @Published private(set) var apiToken: String?
    var hasServerCredentials: Bool {
        !(apiBaseURL?.isEmpty ?? true) && !(apiToken?.isEmpty ?? true)
    }
    private static let baseURLAccount = "apiBaseURL"
    private static let tokenAccount = "apiToken"
    /// 每边档数固定 7（ren 定：表上不提供选择，与手机一致）。
    static let perSide = 7

    private var refreshLoopTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    override init() {
        super.init()
        apiBaseURL = WatchSecrets.load(account: Self.baseURLAccount)
        apiToken = WatchSecrets.load(account: Self.tokenAccount)
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

    // MARK: - 设定执行（直发服务器优先，无凭据回退经手机）

    /// 点间隔的统一入口：有服务器凭据就直发服务器；还没有（手机
    /// 没同步过来）就回退经手机执行的旧通道，保证任何状态下点了都有用。
    func applyStepSelection() {
        if hasServerCredentials {
            Task { await sendGridDirectly() }
        } else {
            pushSelection()
        }
    }

    /// 用手表当前 Swiss 价建网格（规则与手机 buildGrid 一致：起点=
    /// 价格整数部分、起点关闭、上下各 7 档），直接 POST 到服务器。
    func sendGridDirectly() async {
        guard !pushing else { return }
        guard let base = apiBaseURL, let tok = apiToken else {
            pushSelection()
            return
        }
        pushing = true
        defer { pushing = false }
        if swissPrice <= 0 { await refreshPrice() }
        let price = swissPrice
        guard price > 0 else {
            showNotice("还没有取到价格，稍后再试", isError: true)
            return
        }
        let start = Double(Int(price))
        var rows: [(price: Double, enabled: Bool)] = [(start, false)]
        for i in 1...Self.perSide {
            rows.append((start - selectedStep * Double(i), true))
            rows.append((start + selectedStep * Double(i), true))
        }
        rows.sort { $0.price < $1.price }
        do {
            try await WatchAPI.shared.postAlerts(baseURL: base, token: tok, step: selectedStep, rows: rows)
            showNotice("已设定", isError: false)
        } catch {
            showNotice("发送失败：\(error.localizedDescription)", isError: true)
        }
    }

    /// sendMessage 回话看门狗：12 秒内既没回复也没报错就解锁并
    /// 报错。旧版没有这层：手机端不回话时 pushing 永远为真，之后
    /// 每次点间隔都被 guard 静默挡下——点了没反应（ren 2026-11-20 报）。
    private var pushWatchdogTask: Task<Void, Never>?

    func pushSelection() {
        // 点间隔直接触发推送（无按钮）；推送进行中再点不重复发。
        guard !pushing else { return }
        guard WCSession.isSupported() else {
            showNotice("这只手表不支持与手机通信", isError: true)
            return
        }
        let session = WCSession.default
        phoneReachable = session.isReachable
        let message: [String: Any] = [
            "command": "setGrid",
            "step": selectedStep,
            "perSide": Self.perSide,
        ]
        guard session.activationState == .activated else {
            session.activate()
            showNotice("手表还没连上手机，请稍后再点一次", isError: true)
            return
        }
        guard session.isReachable else {
            // 手机 app 当下不可达（没在运行）：排队发送，手机 app
            // 下次被唤醒/打开时由手机端执行；如实告知是排队、不装已生效。
            session.transferUserInfo(message)
            showNotice("手机 app 没在运行，已排队，打开手机 app 后生效", isError: false)
            return
        }
        pushing = true
        pushWatchdogTask?.cancel()
        pushWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if Task.isCancelled { return }
            guard let self, self.pushing else { return }
            self.pushing = false
            self.showNotice("手机 12 秒没回话，请确认手机 app 已打开后重试", isError: true)
        }
        session.sendMessage(message, replyHandler: { [weak self] reply in
            let ok = reply["ok"] as? Bool ?? false
            let text = reply["message"] as? String ?? (ok ? "已设定" : "推送失败")
            Task { @MainActor in
                self?.pushWatchdogTask?.cancel()
                self?.pushing = false
                self?.showNotice(text, isError: !ok)
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.pushWatchdogTask?.cancel()
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

    /// 点「确认全平」：即发即走、不等 EA 结果（ren 定版不变），但
    /// 发送本身的成败必须如实显示——旧版 errorHandler 是空的，消息
    /// 没送达也照样显示「已发送」，ren 2026-11-20 实测不平仓才发现。
    /// 手机 app 没在运行时改走排队：带时间戳发送，手机端只执行
    /// 60 秒内的排队全平（过期的宁可不平，防旧指令误平仓）。
    func closeAllConfirm() {
        guard WCSession.isSupported() else {
            closeAllPhase = .result(text: "这只手表不支持与手机通信", isError: true)
            scheduleCloseAllReset()
            return
        }
        let session = WCSession.default
        phoneReachable = session.isReachable
        guard session.activationState == .activated else {
            session.activate()
            closeAllPhase = .result(text: "手表还没连上手机，请稍后再试", isError: true)
            scheduleCloseAllReset()
            return
        }
        guard session.isReachable else {
            session.transferUserInfo([
                "command": "closeAll",
                "ts": Date().timeIntervalSince1970,
            ])
            closeAllPhase = .result(text: "手机没在运行，已排队：60 秒内打开手机 app 才执行", isError: false)
            scheduleCloseAllReset()
            return
        }
        session.sendMessage(
            ["command": "closeAll"],
            replyHandler: { _ in },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.closeAllPhase = .result(
                        text: "发送失败：\(error.localizedDescription)",
                        isError: true
                    )
                    self?.scheduleCloseAllReset()
                }
            }
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

    /// 手机同步过来的服务器凭据（解锁后与每次打开 app 时推送）：
    /// 存进 Keychain，设定从此可直发服务器、不依赖手机 app 开着。
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let base = applicationContext["apiBaseURL"] as? String
        let tok = applicationContext["apiToken"] as? String
        guard let base, !base.isEmpty, let tok, !tok.isEmpty else { return }
        Task { @MainActor in
            WatchSecrets.save(base, account: Self.baseURLAccount)
            WatchSecrets.save(tok, account: Self.tokenAccount)
            self.apiBaseURL = base
            self.apiToken = tok
        }
    }
}
