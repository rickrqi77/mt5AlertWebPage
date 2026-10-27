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
    @Published var doneFlash = false

    @Published var step: Double = 5
    @Published var alerts: [AlertItem] = []
    @Published var alertsPaused = false
    @Published var alertsDirty = false
    @Published var busy = false
    @Published var eaOnline = false

    private var token = KeychainStore.readToken()
    private var baseURL = KeychainStore.readBaseURL()
    /// EA 推送到服务器、由 /api/status 带回的价格——价格的唯一来源（不再用 Swissquote 金价）。
    @Published private(set) var eaPrice: Double = 0

    /// 画面显示与生成网格用的当前价：完全用 EA 推送价（尚无推送时为 0，画面显示 --）。
    var displayPrice: Double { eaPrice }
    private var cloudTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var doneFlashTask: Task<Void, Never>?

    /// 云端状态（EA 在线小圆点、已触发）轮询间隔。
    private static let cloudPollSeconds: Double = 3

    var armedCount: Int { alerts.filter(\.enabled).count }

    init() {
        if !token.isEmpty {
            isUnlocked = true
        }
        // Show the last-known state instantly; refreshCloudState() updates it in the background.
        alerts = LocalCache.loadAlerts() ?? []
        if let s = LocalCache.loadStep() { step = s }
        if let p = LocalCache.loadPaused() { alertsPaused = p }
        if let o = LocalCache.loadOnline() { eaOnline = o }
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
        eaPrice = 0
        isUnlocked = false
        authError = nil
        LocalCache.clear()
    }

    func startLoops() {
        stopLoops()
        Task { await refreshCloudState() }
        // 定时刷新云端状态：EA 推送价格、在线小圆点（连上后变绿）、已触发的行变成“已用”。
        let cloudNanos = UInt64(Self.cloudPollSeconds * 1_000_000_000)
        cloudTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: cloudNanos)
                await self?.refreshCloudState()
            }
        }
    }

    func stopLoops() {
        cloudTask?.cancel()
        cloudTask = nil
    }

    /// 列表内容指纹（价格+触发+已用），与网页版 alertsFingerprint 同义。
    private static func alertsFingerprint(_ items: [AlertItem]) -> String {
        items.map { "\($0.priceText)|\($0.enabled ? 1 : 0)|\($0.triggered ? 1 : 0)" }
            .joined(separator: ",")
    }

    private func persistState() {
        LocalCache.saveAlerts(alerts)
        LocalCache.saveStep(step)
        LocalCache.savePaused(alertsPaused)
        LocalCache.saveOnline(eaOnline)
    }

    func refreshCloudState() async {
        guard isUnlocked, !token.isEmpty else { return }
        do {
            async let statusReq = CloudflareClient.shared.getStatus(baseURL: baseURL, token: token)
            async let alertsReq = CloudflareClient.shared.getAlerts(baseURL: baseURL, token: token)
            let status = try await statusReq
            let alertsPayload = try await alertsReq
            // 与网页版一致：优先用 /api/status 一并带回的 alerts（与状态同一快照，
            // 是 EA/网站正在用的那份）；/api/alerts 只在 status 没带列表时兜底。
            let remoteDTOs = status.alerts ?? alertsPayload.alerts
            eaOnline = status.ea_online == true
            alertsPaused = status.paused == true || status.alerts_enabled == false
            if let p = status.price, p > 0 { eaPrice = p }
            // 生成/保存进行中不要用服务器的旧 step 覆盖用户刚选的新间隔。
            if !busy, let s = status.step, s > 0 { step = s }
            if !alertsDirty {
                let existing = alerts
                let mapped = remoteDTOs.map { dto -> AlertItem in
                    var item = dto.asItem()
                    // 复用稳定身份（按服务器 id，其次价格），避免刷新时重建行、滚动位置跳回顶部。
                    let byId = existing.first(where: { $0.id != nil && $0.id == item.id })
                    let byPrice = existing.first(where: { $0.priceText == item.priceText })
                    if let match = byId ?? byPrice {
                        item.localID = match.localID
                    }
                    return item
                }
                // 内容指纹没变就不替换列表（同网页版的做法），避免无谓重建行、
                // 以及把刚应用的新设定又换回一份等价/滞后的拷贝。
                if Self.alertsFingerprint(mapped) != Self.alertsFingerprint(existing) {
                    alerts = mapped
                }
            }
            persistState()
        } catch AppError.unauthorized {
            logout()
            authError = "Token 无效"
        } catch {
            // 切入画面/后台刷新失败不弹红色错误提示；3 秒后会自动再刷。
        }
    }

    /// 间隔下拉改动后立刻生效：不再用服务器的生成接口（它在已有设定时只会把新旧
    /// 网格混在一起改一部分），改由本地按间隔逻辑直接算出完整网格，一次保存覆盖服务器。
    ///
    /// 间隔逻辑（ren 定版）：以当前 EA 价格取整为中心点，从中心向前、向后各按间隔
    /// 空出点数设定，前后各 7 个、加上中心共 15 个；除中心点外其余全部设为有效（触发），
    /// 中心点设为关闭（现价就在该点上，避免立即触发）。
    /// 全过程画面保持旧列表不动，保存成功后一次性替换；失败则什么都不变。
    func applyStep(_ value: Double) async {
        let previousStep = step
        let wasDirty = alertsDirty
        step = value
        persistState()

        busy = true
        defer { busy = false }
        alertsDirty = true

        // 价格完全用 EA 推送价：先刷新一次状态拿到最新推送价。
        await refreshCloudState()
        let price = eaPrice
        guard price > 0 else {
            alertsDirty = wasDirty
            step = previousStep
            persistState()
            showToast("还没有 EA 价格", error: true)
            return
        }

        let grid = Self.buildGrid(centerPrice: price, step: value)
        do {
            let data = try await CloudflareClient.shared.saveAlerts(
                baseURL: baseURL,
                token: token,
                alerts: grid,
                step: value
            )
            // 一次性替换显示：优先用服务器回显（带 id），没有就用本地算好的网格。
            alerts = (data.alerts ?? []).map { $0.asItem() }
            if alerts.isEmpty { alerts = grid }
            alertsDirty = false
            persistState()
            flashDone()
        } catch {
            alertsDirty = wasDirty
            step = previousStep
            persistState()
            showToast(error.localizedDescription, error: true)
        }
    }

    /// 按间隔逻辑本地生成网格：中心 = 当前价取整；中心 ± 间隔×1..7；升序排列；
    /// 中心点关闭（enabled=false），其余全部触发（enabled=true），均未触发过。
    private static func buildGrid(centerPrice: Double, step: Double) -> [AlertItem] {
        let center = centerPrice.rounded()
        return (-7...7).map { offset in
            let point = center + Double(offset) * step
            return AlertItem(
                id: nil,
                priceText: String(format: "%.2f", point),
                enabled: offset != 0,
                triggered: false
            )
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
            persistState()
            flashDone()
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
            persistState()
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
            persistState()
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
        // 行视图 onAppear 会回显一次相同价格，此时不应标记 dirty；
        // 只有用户真正改了价格才标记，避免云端刷新被挡住、已触发状态无法更新。
        guard alerts[index].priceText != text else { return }
        alerts[index].priceText = text
        alertsDirty = true
    }

    func flashDone() {
        doneFlash = true
        doneFlashTask?.cancel()
        doneFlashTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                doneFlash = false
            }
        }
    }

    func showToast(_ message: String, error: Bool) {
        toast = message
        toastIsError = error
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled {
                toast = nil
            }
        }
    }

}
