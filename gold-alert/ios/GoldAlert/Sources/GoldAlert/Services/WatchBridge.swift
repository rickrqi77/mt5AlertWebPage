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

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

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
        guard (message["command"] as? String) == "setGrid",
              let step = (message["step"] as? NSNumber)?.doubleValue,
              let perSide = (message["perSide"] as? NSNumber)?.intValue else {
            replyHandler(["ok": false, "message": "指令格式不对"])
            return
        }
        Task { @MainActor in
            guard let handler = WatchBridge.shared.onSetGridCommand else {
                replyHandler(["ok": false, "message": "手机端还没准备好"])
                return
            }
            let (ok, text) = await handler(step, perSide)
            replyHandler(["ok": ok, "message": text])
        }
    }
}
