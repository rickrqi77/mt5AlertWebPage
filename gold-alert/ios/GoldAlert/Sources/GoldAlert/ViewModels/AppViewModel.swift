import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    static let maxAlerts = 15
    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]
    static let pollChoices: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 30]
    private static let pollSecondsKey = "pricePollSeconds"

    @Published var isUnlocked = false
    @Published var tokenInput = ""
    @Published var baseURLInput = KeychainStore.readBaseURL()
    @Published var authError: String?
    @Published var toast: String?
    @Published var toastIsError = false

    @Published var quote = Quote.empty
    @Published var lastRefreshText = "--"
    @Published var step: Double = 5
    @Published var pollSeconds: Double = AppViewModel.loadPollSeconds()
    @Published var alerts: [AlertItem] = []
    @Published var alertsPaused = false
    @Published var alertsDirty = false
    @Published var busy = false
    @Published var eaOnline = false

    private var token = KeychainStore.readToken()
    private var baseURL = KeychainStore.readBaseURL()
    private var priceTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    var armedCount: Int { alerts.filter(\.enabled).count }

    init() {
        if !token.isEmpty {
            isUnlocked = true
        }
    }

    func setPollSeconds(_ seconds: Double) {
        let allowed = Self.pollChoices
        let value = allowed.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? 1
        pollSeconds = value
        UserDefaults.standard.set(value, forKey: Self.pollSecondsKey)
        if isUnlocked {
            startLoops()
        }
        showToast("刷新间隔 \(Self.pollLabel(value))", error: false)
    }

    private static func loadPollSeconds() -> Double {
        let stored = UserDefaults.standard.object(forKey: pollSecondsKey) as? Double
        let value = stored ?? 1
        if pollChoices.contains(where: { abs($0 - value) < 1e-9 }) {
            return value
        }
        return 1
    }

    private static func pollLabel(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.1f 秒", seconds)
        }
        if abs(seconds - seconds.rounded()) < 1e-9 {
            return "\(Int(seconds)) 秒"
        }
        return String(format: "%.1f 秒", seconds)
    }

    func onAppear() {
        guard isUnlocked else { return }
        startLoops()
    }

    func unlock() async {
        authError = nil
        let t = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !t.isEmpty else {
            authError = "请输入 API Token"
            return
        }
        guard !base.isEmpty else {
            authError = "请输入 Cloudflare 地址"
            return
        }

        busy = true
        defer { busy = false }
        do {
            try await CloudflareClient.shared.unlock(baseURL: base, token: t)
            token = t
            baseURL = base
            KeychainStore.saveToken(t)
            KeychainStore.saveBaseURL(base)
            tokenInput = ""
            isUnlocked = true
            startLoops()
            showToast("已解锁", error: false)
        } catch {
            authError = error.localizedDescription
            isUnlocked = false
        }
    }

    func logout() {
        stopLoops()
        KeychainStore.clearToken()
        token = ""
        tokenInput = ""
        alerts = []
        quote = .empty
        isUnlocked = false
        authError = nil
    }

    func startLoops() {
        stopLoops()
        Task { await refreshCloudState() }
        let nanos = UInt64(max(pollSeconds, 0.5) * 1_000_000_000)
        priceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSwissquote()
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stopLoops() {
        priceTask?.cancel()
        priceTask = nil
    }

    /// Swissquote is display-only on device. Cloudflare only gets alert/settings for the EA.
    func refreshSwissquote() async {
        guard isUnlocked else { return }
        do {
            let q = try await SwissquoteClient.shared.fetchQuote()
            quote = q
            lastRefreshText = "现货 " + Self.clockString()
        } catch {
            if quote.price <= 0 {
                showToast(error.localizedDescription, error: true)
            }
        }
    }

    func refreshCloudState() async {
        guard isUnlocked, !token.isEmpty else { return }
        do {
            async let statusReq = CloudflareClient.shared.getStatus(baseURL: baseURL, token: token)
            async let alertsReq = CloudflareClient.shared.getAlerts(baseURL: baseURL, token: token)
            let status = try await statusReq
            let remote = try await alertsReq
            eaOnline = status.ea_online == true
            alertsPaused = status.paused == true || status.alerts_enabled == false
            if let s = status.step, s > 0 { step = s }
            if !alertsDirty {
                alerts = remote.alerts.map { $0.asItem() }
            }
        } catch AppError.unauthorized {
            logout()
            authError = "Token 无效"
        } catch {
            showToast(error.localizedDescription, error: true)
        }
    }

    func autoGenerate() async {
        guard quote.isValid else {
            showToast("还没有现货价格", error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            // Auto uses local Swissquote mid only to build the grid; EA still owns live price.
            let data = try await CloudflareClient.shared.autoGenerate(
                baseURL: baseURL,
                token: token,
                step: step,
                price: quote.price
            )
            alerts = (data.alerts ?? []).map { $0.asItem() }
            alertsDirty = false
            if let s = data.step, s > 0 { step = s }
            showToast(data.message ?? "已生成", error: false)
        } catch {
            showToast(error.localizedDescription, error: true)
        }
    }

    func saveAlerts() async {
        for item in alerts {
            guard let p = item.priceValue, p > 0 else {
                showToast("存在无效价格：\(item.priceText)", error: true)
                return
            }
        }
        guard alerts.count <= Self.maxAlerts else {
            showToast("最多 \(Self.maxAlerts) 个提醒", error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let data = try await CloudflareClient.shared.saveAlerts(
                baseURL: baseURL,
                token: token,
                alerts: alerts,
                step: step
            )
            alerts = (data.alerts ?? []).map { $0.asItem() }
            alertsDirty = false
            showToast("设置已保存，EA 下次同步时取回", error: false)
        } catch {
            showToast(error.localizedDescription, error: true)
        }
    }

    func clearAll() async {
        alerts = []
        alertsDirty = true
        busy = true
        defer { busy = false }
        do {
            _ = try await CloudflareClient.shared.saveAlerts(
                baseURL: baseURL,
                token: token,
                alerts: [],
                step: step
            )
            alertsDirty = false
            showToast("已全部清除", error: false)
        } catch {
            showToast(error.localizedDescription, error: true)
        }
    }

    func togglePause() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await CloudflareClient.shared.setPaused(
                baseURL: baseURL,
                token: token,
                paused: !alertsPaused
            )
            alertsPaused = data.paused ?? !alertsPaused
        } catch {
            showToast(error.localizedDescription, error: true)
        }
    }

    func toggleArm(at index: Int) {
        guard alerts.indices.contains(index) else { return }
        alerts[index].enabled.toggle()
        if alerts[index].enabled {
            alerts[index].triggered = false
        }
        alertsDirty = true
    }

    func deleteAlert(at index: Int) {
        guard alerts.indices.contains(index) else { return }
        alerts.remove(at: index)
        alertsDirty = true
    }

    func updatePrice(at index: Int, text: String) {
        guard alerts.indices.contains(index) else { return }
        alerts[index].priceText = text
        alertsDirty = true
    }

    func showToast(_ message: String, error: Bool) {
        toast = message
        toastIsError = error
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled {
                toast = nil
            }
        }
    }

    private static func clockString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
