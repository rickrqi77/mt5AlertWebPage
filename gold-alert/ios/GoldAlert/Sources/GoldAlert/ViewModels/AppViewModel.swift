import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    static let maxAlerts = 15
    static let stepChoices: [Double] = [1, 2, 3, 4, 5, 10]

    @Published var isUnlocked = false
    @Published var tokenInput = ""
    @Published var baseURLInput = KeychainStore.readBaseURL()
    @Published var authError: String?
    @Published var toast: String?
    @Published var toastIsError = false

    @Published var quote = Quote.empty
    @Published var priceLabel = "Swissquote"
    @Published var lastRefreshText = "--"
    @Published var step: Double = 5
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
        priceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSwissquoteAndUpload()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopLoops() {
        priceTask?.cancel()
        priceTask = nil
    }

    /// App-side price path: Swissquote → show → upload Cloudflare (EA still syncs separately).
    func refreshSwissquoteAndUpload() async {
        guard isUnlocked, !token.isEmpty else { return }
        do {
            let q = try await SwissquoteClient.shared.fetchQuote()
            quote = q
            priceLabel = "Swissquote"
            lastRefreshText = "现货 " + Self.clockString()
            _ = try await CloudflareClient.shared.uploadPrice(
                baseURL: baseURL,
                token: token,
                quote: q
            )
        } catch {
            // Keep last good quote; surface transient errors lightly.
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
            showToast("还没有 Swissquote 价格", error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            // Ensure Cloudflare has the same mid before auto (and for any other clients).
            _ = try await CloudflareClient.shared.uploadPrice(
                baseURL: baseURL,
                token: token,
                quote: quote
            )
            let data = try await CloudflareClient.shared.autoGenerate(
                baseURL: baseURL,
                token: token,
                step: step,
                price: quote.price
            )
            alerts = (data.alerts ?? []).map { $0.asItem() }
            alertsDirty = false
            if let s = data.step, s > 0 { step = s }
            showToast(data.message ?? "已生成，默认全部触发", error: false)
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
            showToast(data.message ?? (alertsPaused ? "提醒已暂停" : "提醒已恢复"), error: false)
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
