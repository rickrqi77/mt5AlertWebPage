import Foundation
import SwiftUI

/// 实时价格来源（ren 2026-10-28 要求在「提醒事项」菜单里可选）：
/// EA = 用 EA 推送到服务器的价格；Swiss = 直接取 Swissquote 的 XAU/USD 报价。
/// 选定后持久化，下次打开默认沿用。
enum PriceSource: String, CaseIterable, Identifiable {
    case ea = "EA"
    case swiss = "Swiss"

    var id: String { rawValue }
}

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
    private static let priceSourceKey = "priceSource"

    /// EA 推送到服务器、由 /api/status 带回的价格。
    @Published private(set) var eaPrice: Double = 0
    /// Swissquote 的 XAU/USD 报价（选 Swiss 来源时用，Swiss 模式下 1 秒刷新一次）。
    @Published private(set) var swissPrice: Double = 0
    /// 当前实时价格来源（「提醒事项」菜单里切换，持久化）。
    @Published var priceSource: PriceSource = .ea

    /// 画面显示与生成网格用的当前价：按所选来源取 EA 推送价或 Swiss 报价
    ///（尚无价格时为 0，画面显示 --）。
    var displayPrice: Double { priceSource == .ea ? eaPrice : swissPrice }
    private var cloudTask: Task<Void, Never>?
    private var swissTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var doneFlashTask: Task<Void, Never>?

    /// 云端状态（EA 在线小圆点、已触发）轮询间隔。
    private static let cloudPollSeconds: Double = 3

    var armedCount: Int { alerts.filter(\.enabled).count }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.priceSourceKey),
           let saved = PriceSource(rawValue: raw) {
            priceSource = saved
        }
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
        swissPrice = 0
        isUnlocked = false
        authError = nil
        LocalCache.clear()
    }

    func startLoops() {
        stopLoops()
        Task {
            await refreshCloudState()
            await refreshSwissPrice()
        }
        // 定时刷新云端状态：EA 推送价格、在线小圆点（连上后变绿）、已触发的行变成“已用”。
        let cloudNanos = UInt64(Self.cloudPollSeconds * 1_000_000_000)
        cloudTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: cloudNanos)
                await self?.refreshCloudState()
            }
        }
        // Swiss 模式专属的 1 秒报价轮询（ren 2026-10-28 定）：循环常开，
        // refreshSwissPrice 内部按当前来源把关——EA 模式下每秒只是空转不取价。
        swissTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.refreshSwissPrice()
            }
        }
    }

    /// 「提醒事项」菜单里切换实时价格来源：设定后持久化，下次打开默认沿用；
    /// 切到 Swiss 时立刻取一次报价，不等下一个轮询周期。
    func setPriceSource(_ source: PriceSource) {
        priceSource = source
        UserDefaults.standard.set(source.rawValue, forKey: Self.priceSourceKey)
        if source == .swiss {
            Task { await refreshSwissPrice() }
        }
    }

    /// 刷新 Swissquote 黄金报价（仅来源选 Swiss 时才取）；失败静默、保留上次的值。
    func refreshSwissPrice() async {
        guard priceSource == .swiss else { return }
        if let quote = try? await SwissquoteClient.shared.fetchQuote(), quote.price > 0 {
            swissPrice = quote.price
        }
    }

    func stopLoops() {
        cloudTask?.cancel()
        cloudTask = nil
        swissTask?.cancel()
        swissTask = nil
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
                    // 复用稳定身份（id 与价格都对上才算同一行，其次按价格），
                    // 避免刷新时重建行、滚动位置跳回顶部；价格不同绝不继承身份，
                    // 否则新设定的一行会被误认成旧设定同价的那一行。
                    let byId = existing.first(where: { $0.id != nil && $0.id == item.id && $0.priceText == item.priceText })
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

    /// 间隔下拉改动后立刻生效：本地按间隔逻辑直接算出完整网格，一次保存覆盖服务器。
    /// （2026-10-27 实测服务器：POST /api/alerts 与 /api/alerts/auto 都是整表替换、
    /// 不合并，EA 同步也不会把旧设定带回来；截图里的新旧混合出在 app 行视图：
    /// 行按位置（.id(index)）复用 + 行内 @State 价格草稿残留同行号旧值。
    /// 现已拆除草稿——价格直接显示模型值，行身份统一用 AlertItem.rowKey。）
    ///
    /// 间隔逻辑（ren 定版）：先确定当前显示价格（来源可选 EA/Swiss）的整数部分（只取整数、小数直接舍去，
    /// 不是四舍五入），以这个整数为起点，往小按间隔设 7 个、往大按间隔设 7 个，
    /// 加上起点本身共 15 个；全部设完后按价格升序排序显示。
    /// 除起点外其余全部设为有效（触发），起点设为关闭（现价就在该点附近，避免立即触发）。
    ///
    /// 推送顺序（ren 定版）：价格定下来、网格算好后，先把新网格刷新到画面上；
    /// 之后等到下一次推送时间（一个 3 秒同步周期，EA 同步与云端轮询都是 3 秒）
    /// 再把这份网格推给服务器。等待期间 busy+alertsDirty 保持锁定，
    /// 后台轮询不许用服务器上的旧设定盖掉画面刚显示的新网格。
    /// 推送失败时画面不回退：新网格继续留在画面上、保持锁定，用户可点「保存」重试。
    ///
    /// 「立刻刷新」的关键：定价直接用画面上正在显示的价格（displayPrice 按所选来源取 EA 推送价或 Swiss 报价，本来就由
    /// 3 秒轮询保持最新），算网格、换列表全部在第一个 await 之前同步完成——
    /// 旧版先 await 一次网络刷新才换列表，画面要等网络回来才动，
    /// 看起来就像等到下一次价格更新才刷新（ren 21:35 实测反馈）。
    func applyStep(_ value: Double) async {
        let previousStep = step
        let wasDirty = alertsDirty
        step = value
        persistState()

        busy = true
        defer { busy = false }
        alertsDirty = true

        // 价格就此定下：用画面当前显示的价格（按所选来源：EA 推送价或 Swiss 报价），
        // 不先等网络。
        var price = displayPrice
        if price <= 0 {
            // 只有当前来源还从未取到过价（画面显示 --）时，才现取一次兜底。
            if priceSource == .ea {
                await refreshCloudState()
            } else {
                await refreshSwissPrice()
            }
            price = displayPrice
        }
        guard price > 0 else {
            alertsDirty = wasDirty
            step = previousStep
            persistState()
            showToast(priceSource == .ea ? "还没有 EA 价格" : "还没有 Swiss 价格", error: true)
            return
        }

        let grid = Self.buildGrid(centerPrice: price, step: value)

        // 第一步：立刻刷新画面——新网格当场显示，不等网络、不等下一次价格更新。
        alerts = grid
        persistState()

        // 第二步：等下一次推送时间到（一个 3 秒周期）再推给服务器。
        try? await Task.sleep(nanoseconds: UInt64(Self.cloudPollSeconds * 1_000_000_000))

        do {
            let data = try await CloudflareClient.shared.saveAlerts(
                baseURL: baseURL,
                token: token,
                alerts: grid,
                step: value
            )
            // 推送完成：服务器回显与画面网格内容一致时保留画面这份、不再整表替换，
            // 避免推送后画面无谓地再重建一次；不一致时才以服务器回显为准。
            let echoed = (data.alerts ?? []).map { $0.asItem() }
            if !echoed.isEmpty, Self.alertsFingerprint(echoed) != Self.alertsFingerprint(grid) {
                alerts = echoed
            }
            alertsDirty = false
            persistState()
            flashDone()
        } catch {
            // 已先刷新画面，失败也不把画面退回旧设定；保持锁定防轮询盖回，
            // 提示后用户可点「保存」把画面这份网格重试推送。
            alertsDirty = true
            persistState()
            showToast(error.localizedDescription, error: true)
        }
    }

    /// 按间隔逻辑本地生成网格（ren 定版，严格按此顺序）：
    /// 1. 起点 = 当前价的整数部分（Int 直接截断小数，不四舍五入；
    ///    例：4013.80 的起点是 4013，不是 4014。服务器 /api/alerts/auto 同样用 4013，
    ///    旧版用 rounded() 四舍五入是小数 ≥.5 时整格错位 1 的根源）；
    /// 2. 从起点往小设 7 个：起点 − 间隔×1...7；
    /// 3. 从起点往大设 7 个：起点 + 间隔×1...7；
    /// 4. 全部设完后按价格升序排序。
    /// 起点关闭（enabled=false），其余全部触发（enabled=true），均未触发过。
    private static func buildGrid(centerPrice: Double, step: Double) -> [AlertItem] {
        let start = Double(Int(centerPrice))
        var points: [(price: Double, isStart: Bool)] = [(start, true)]
        for i in 1...7 {
            points.append((start - step * Double(i), false))
        }
        for i in 1...7 {
            points.append((start + step * Double(i), false))
        }
        return points
            .sorted { $0.price < $1.price }
            .map { point in
                AlertItem(
                    id: nil,
                    priceText: String(format: "%.2f", point.price),
                    enabled: !point.isStart,
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

    /// 底部按钮是否处于「全设定」模式：列表非空、且全部提醒都关着。
    var allAlertsDisabled: Bool {
        !alerts.isEmpty && alerts.allSatisfy { !$0.enabled }
    }

    /// 「全取消」：不删除画面上的列表，只把所有提醒关掉，并立即保存到
    /// 服务器（ren 2026-10-28 改定，取代原「清除」删列表的行为）。
    func disableAllAlerts() async {
        for index in alerts.indices {
            alerts[index].enabled = false
        }
        alertsDirty = true
        await saveAlerts()
    }

    /// 「全设定」：除第 8 项（第 8 行、网格起点）保持关闭外，其余全部打开
    /// （打开的项清掉已触发标记、重新待命，与单行 toggleArm 一致），
    /// 并立即保存到服务器（ren 2026-10-28）。
    func enableAllAlerts() async {
        for index in alerts.indices {
            if index == 7 {
                alerts[index].enabled = false
            } else {
                alerts[index].enabled = true
                alerts[index].triggered = false
            }
        }
        alertsDirty = true
        await saveAlerts()
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
