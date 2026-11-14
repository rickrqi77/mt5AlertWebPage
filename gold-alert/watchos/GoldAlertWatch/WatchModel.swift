import Foundation
import WatchConnectivity

/// 手表端状态与流程：
/// - 价格：优先 EA 推送到服务器的价格（/api/status），取不到时用 Swissquote
///   公共报价兜底显示（凭据还没同步过来时也能看价）；
/// - 间隔：与手机端同一组选项 [1, 2, 3, 4, 5, 10]，首次打开默认跟随服务器
///   当前间隔；点「设定并推送」后 POST /api/alerts/auto，服务器按现价生成
///   网格（上下各 7 个、共 15 个，与手机端一致）并保存，EA 下个同步周期采用；
/// - 凭据：iPhone 端解锁后经 WatchConnectivity 的 applicationContext 同步
///   {baseURL, token}，收到后存手表自己的钥匙串；手机端退出登录会同步清空。
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var eaPrice: Double = 0
    @Published var swissPrice: Double = 0
    @Published var eaOnline = false
    @Published var serverStep: Double = 0
    @Published var armedCount = 0
    @Published var totalCount = 0
    @Published var selectedStep: Double = 5
    @Published var hasCredentials = false
    @Published var busy = false
    @Published var pushing = false
    @Published var notice: String?
    @Published var noticeIsError = false
    @Published var lastUpdated: Date?

    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]

    private var baseURL = WatchKeychain.readBaseURL()
    private var token = WatchKeychain.readToken()
    private var didInitStepFromServer = false
    private var refreshLoopTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    var displayPrice: Double { eaPrice > 0 ? eaPrice : swissPrice }
    var priceSourceText: String {
        if eaPrice > 0 { return "EA" }
        if swissPrice > 0 { return "Swiss" }
        return ""
    }

    override init() {
        super.init()
        hasCredentials = !token.isEmpty
        activateSession()
    }

    // MARK: - 价格刷新

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        if let price = try? await WatchAPI.shared.fetchSwissPrice() {
            swissPrice = price
            if eaPrice <= 0 { lastUpdated = Date() }
        }

        guard hasCredentials else { return }
        do {
            let status = try await WatchAPI.shared.getStatus(baseURL: baseURL, token: token)
            if let p = status.price, p > 0 { eaPrice = p }
            eaOnline = status.ea_online ?? false
            if let s = status.step, s > 0 {
                serverStep = s
                if !didInitStepFromServer {
                    selectedStep = s
                    didInitStepFromServer = true
                }
            }
            if let list = status.alerts {
                totalCount = list.count
                armedCount = list.filter { $0.enabled?.boolValue ?? true }.count
            }
            lastUpdated = Date()
        } catch let error as WatchAPIError {
            if case .unauthorized = error {
                showNotice(error.localizedDescription, isError: true)
            }
        } catch {
            // 网络抖动时静默：画面保留上次价格，下个周期再刷。
        }
    }

    func startAutoRefresh() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    // MARK: - 推送间隔设定到 EA

    func pushSelectedStep() async {
        guard hasCredentials else {
            showNotice("先在 iPhone 上打开提醒事项解锁一次，凭据会自动同步到手表", isError: true)
            return
        }
        let price = displayPrice
        guard price > 0 else {
            showNotice("还没有价格，稍后再试", isError: true)
            return
        }
        pushing = true
        defer { pushing = false }
        do {
            _ = try await WatchAPI.shared.autoGenerate(
                baseURL: baseURL,
                token: token,
                step: selectedStep,
                price: price
            )
            serverStep = selectedStep
            didInitStepFromServer = true
            showNotice("已推送 · 间隔 \(Self.formatStep(selectedStep)) · EA 数秒内生效", isError: false)
            // 等 EA 一个同步周期后再刷新，让“已设定个数”显示新网格。
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await refresh()
        } catch {
            showNotice(error.localizedDescription, isError: true)
        }
    }

    static func formatStep(_ step: Double) -> String {
        String(format: "%.0f", step)
    }

    private func showNotice(_ text: String, isError: Bool) {
        notice = text
        noticeIsError = isError
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if Task.isCancelled { return }
            self?.notice = nil
        }
    }

    // MARK: - WatchConnectivity（接收 iPhone 同步的凭据）

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func applyCredentials(baseURL newBase: String, token newToken: String) {
        if newToken.isEmpty {
            WatchKeychain.clearToken()
            token = ""
            hasCredentials = false
            return
        }
        token = newToken
        WatchKeychain.saveToken(newToken)
        if !newBase.isEmpty {
            baseURL = newBase
            WatchKeychain.saveBaseURL(newBase)
        }
        hasCredentials = true
        Task { await refresh() }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // 激活完成后，若 iPhone 先前已写入 applicationContext，
        // 系统会紧接着回调 didReceiveApplicationContext。
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let newToken = applicationContext["token"] as? String ?? ""
        let newBase = applicationContext["baseURL"] as? String ?? ""
        Task { @MainActor in
            self.applyCredentials(baseURL: newBase, token: newToken)
        }
    }
}
