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
    @Published var doneFlash = false

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
    /// 服务器 /api/status 带回的 EA 价格（与网页版「设定」用的 spotPrice 同源），
    /// 现货报价取不到时生成提醒网格用它兜底。
    private var lastEAStatusPrice: Double = 0
    private var priceTask: Task<Void, Never>?
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
        LocalCache.clear()
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
        // 定时刷新云端状态：EA 在线小圆点（连上后变绿）、已触发的行变成“已用”。
        let cloudNanos = UInt64(Self.cloudPollSeconds * 1_000_000_000)
        cloudTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: cloudNanos)
                await self?.refreshCloudState()
            }
        }
    }

    func stopLoops() {
        priceTask?.cancel()
        priceTask = nil
        cloudTask?.cancel()
        cloudTask = nil
    }

    private func persistState() {
        LocalCache.saveAlerts(alerts)
        LocalCache.saveStep(step)
        LocalCache.savePaused(alertsPaused)
        LocalCache.saveOnline(eaOnline)
    }

    /// Swissquote is display-only on device. Cloudflare only gets alert/settings for the EA.
    func refreshSwissquote() async {
        guard isUnlocked else { return }
        do {
            let q = try await SwissquoteClient.shared.fetchQuote()
            quote = q
            lastRefreshText = "现货 " + Self.clockString()
        } catch {
            // 切入画面/后台刷新失败不弹红色错误提示；循环会继续自动重试。
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
            if let p = status.price, p > 0 { lastEAStatusPrice = p }
            // 生成/保存进行中不要用服务器的旧 step 覆盖用户刚选的新间隔。
            if !busy, let s = status.step, s > 0 { step = s }
            if !alertsDirty {
                let existing = alerts
                alerts = remote.alerts.map { dto in
                    var item = dto.asItem()
                    // 复用稳定身份（按服务器 id，其次价格），避免刷新时重建行、滚动位置跳回顶部。
                    let byId = existing.first(where: { $0.id != nil && $0.id == item.id })
                    let byPrice = existing.first(where: { $0.priceText == item.priceText })
                    if let match = byId ?? byPrice {
                        item.localID = match.localID
                    }
                    return item
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

    /// 间隔下拉改动后立刻生效：更新间隔，并按当前价重新生成提醒网格（原「设定」按钮的动作），
    /// 生成结果由服务器保存，下方提醒随之更新、网站同步。失败会弹提示，不静默。
    func applyStep(_ value: Double) async {
        step = value
        persistState()
        await autoGenerate()
    }

    func autoGenerate() async {
        // 先把要用的间隔定住：下面兜底刷新云端状态时可能用服务器旧值覆盖 step，
        // 生成请求必须用用户刚选的这个值，不能被覆盖掉。
        let stepToUse = step
        // 建网格用的价格：先现货价；取不到就先刷新一次，再用服务器带回的 EA 价格兜底
        //（网页版「设定」用的正是 /api/status 的 EA 价格）。都没有才提示。
        var price = quote.price
        if !quote.isValid {
            await refreshSwissquote()
            price = quote.price
        }
        if price <= 0 {
            await refreshCloudState()
            price = lastEAStatusPrice
        }
        guard price > 0 else {
            showToast("还没有现货价格", error: true)
            return
        }
        busy = true
        defer { busy = false }
        // 生成全程把列表锁住（alertsDirty=true）：3 秒一次的云端轮询在此期间
        // 不许用服务器上的旧设定盖掉正在生成/刚生成的新列表——此前有设定时改间隔
        // 看似没反应，就是新列表生成后又被轮询并发的旧数据盖回（清空后无旧数据可盖，才偶尔看似有效）。
        let wasDirty = alertsDirty
        alertsDirty = true
        do {
            let data = try await CloudflareClient.shared.autoGenerate(
                baseURL: baseURL,
                token: token,
                step: stepToUse,
                price: price
            )
            alerts = (data.alerts ?? []).map { $0.asItem() }
            if let s = data.step, s > 0 { step = s } else { step = stepToUse }
        } catch {
            alertsDirty = wasDirty
            showToast(error.localizedDescription, error: true)
            return
        }
        // 紧接着把生成结果保存到服务器（等同于生成后再点一次「保存」），确保网站/EA
        // 一定拿到新设定，不依赖 /api/alerts/auto 本身是否落库。
        do {
            let saved = try await CloudflareClient.shared.saveAlerts(
                baseURL: baseURL,
                token: token,
                alerts: alerts,
                step: step
            )
            if let savedAlerts = saved.alerts {
                alerts = savedAlerts.map { $0.asItem() }
            }
            alertsDirty = false
            persistState()
            flashDone()
        } catch {
            // 生成结果已在本地显示；保存没成功就保持列表锁定（轮询不盖回），
            // 提示用户可再点「保存」推送到网站。
            showToast("已生成，但保存到网站失败：\(error.localizedDescription)", error: true)
            persistState()
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

    private static func clockString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
