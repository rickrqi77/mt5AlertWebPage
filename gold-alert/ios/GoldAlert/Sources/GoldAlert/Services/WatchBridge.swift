import Foundation
import WatchConnectivity

/// 手机与手表的桥（ren 2026-11-15 定：执行留在手机上）：
/// 手表只把 {间隔, 每边档数} 经 sendMessage 发过来，手机用现有的建网格
/// 逻辑生成网格并 POST /api/alerts，再把结果回传给手表显示。
/// token 和服务器地址只留在手机上，不同步给手表。
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// 手表设定指令的处理者，由 AppViewModel 在 init 时注册：
    /// 入参 (间隔, 每边档数)，返回 (是否成功, 给手表显示的结果文案)。
    var onSetGridCommand: ((Double, Int) async -> (Bool, String))?

    /// 手表一键全平的处理者（下指令即返回，不等 EA 结果），
    /// 返回直接回给手表的字典。
    var onCloseAll: (() async -> [String: Any])?

    /// 当前凭据提供者（AppViewModel 注册）：会话刚激活完成时若
    /// 已有凭据，顺手同步一次给手表，堵住「解锁时会话还没激活、
    /// 同步被跳过」的时序缝。
    var credentialsProvider: (() -> (baseURL: String, token: String)?)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 把服务器地址+token 同步给手表（ren 2026-11-20 改定：手表
    /// 设定直发服务器，不再经手机中转）。走 applicationContext：
    /// 系统持久保存、手表 app 下次打开也必送达，解锁后与每次打开
    /// app 时各推一次，保证手表上存的始终是当前凭据。
    func pushCredentialsToWatch(baseURL: String, token: String) {
        guard WCSession.isSupported(), !baseURL.isEmpty, !token.isEmpty else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext([
            "apiBaseURL": baseURL,
            "apiToken": token,
        ])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let c = WatchBridge.shared.credentialsProvider?() {
                WatchBridge.shared.pushCredentialsToWatch(baseURL: c.baseURL, token: c.token)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    /// 手表点「设定并推送」时发来的即时消息：必须回 replyHandler，
    /// 手表靠这个回复显示成功/失败（手机不在附近时消息根本到不了这里，
    /// 手表端会自己报连接失败）。
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let command = message["command"] as? String
        if command == "closeAll" {
            nonisolated(unsafe) let reply = replyHandler
            Task { @MainActor in
                guard let handler = WatchBridge.shared.onCloseAll else {
                    reply(["ok": false, "message": "手机端还没准备好"])
                    return
                }
                reply(await handler())
            }
            return
        }
        guard command == "setGrid",
              let step = (message["step"] as? NSNumber)?.doubleValue,
              let perSide = (message["perSide"] as? NSNumber)?.intValue else {
            replyHandler(["ok": false, "message": "指令格式不对"])
            return
        }
        // replyHandler 是系统保证只回一次、可跨队列调用的句柄，但
        // Swift 6 并发检查推不出这一点，进 @MainActor Task 前用
        // nonisolated(unsafe) 放行（与史记 WatchBridge 同一处理）。
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            guard let handler = WatchBridge.shared.onSetGridCommand else {
                reply(["ok": false, "message": "手机端还没准备好"])
                return
            }
            let (ok, text) = await handler(step, perSide)
            reply(["ok": ok, "message": text])
        }
    }

    /// 排队消息（transferUserInfo）：手表在手机 app 没运行时点间隔/
    /// 全平会走这条通道，消息在手机 app 下次被唤醒/打开时送达。
    /// setGrid 直接执行同一处理者（无回话，执行结果手机上以 toast
    /// 显示）；closeAll 带时间戳，只执行 60 秒内的——过期的排队
    /// 全平宁可丢弃，防旧指令在不合时宜时误平仓。
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let command = userInfo["command"] as? String
        if command == "closeAll" {
            let ts = (userInfo["ts"] as? NSNumber)?.doubleValue ?? 0
            guard Date().timeIntervalSince1970 - ts <= 60 else { return }
            Task { @MainActor in
                _ = await WatchBridge.shared.onCloseAll?()
            }
            return
        }
        guard command == "setGrid",
              let step = (userInfo["step"] as? NSNumber)?.doubleValue,
              let perSide = (userInfo["perSide"] as? NSNumber)?.intValue else {
            return
        }
        Task { @MainActor in
            _ = await WatchBridge.shared.onSetGridCommand?(step, perSide)
        }
    }
}
