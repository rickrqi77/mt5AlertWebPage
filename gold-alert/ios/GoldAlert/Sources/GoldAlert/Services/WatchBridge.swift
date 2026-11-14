import Foundation
import WatchConnectivity

/// 把已解锁的 API 凭据同步给手表端：WatchConnectivity 的
/// updateApplicationContext 会把最新一份 {baseURL, token} 留在系统里，
/// 手表端下次激活/打开时自动收到，存进它自己的钥匙串。之后手表可独立
/// 联网取价、在表上选间隔推送到 EA，不依赖手机实时在线。
/// 手机端退出登录时同步一份空凭据，手表随之清掉自己的凭据。
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func syncCredentials(baseURL: String, token: String) {
        guard WCSession.isSupported() else { return }
        let context: [String: Any] = ["baseURL": baseURL, "token": token]
        // 未配对/手表端未装时系统会报错，忽略即可：下次解锁或打开 app 时会再同步。
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate（iOS 端只需处理去激活后重新激活）

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
