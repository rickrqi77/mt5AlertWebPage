import SwiftUI

@main
struct GoldAlertApp: App {
    @StateObject private var model = AppViewModel()

    init() {
        // 手表指令通道在 app 入口就激活（包括被手表消息后台唤醒的
        // 进程）：不等视图/视图模型创建，确保手表点间隔/全平的消息
        // 有委托接收（AppViewModel.init 里也会再激活一次，重复无害）。
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // 画面固定深色模式，不管系统外观如何设定（ren 2026-10-28 改定，
                // 覆盖此前「跟随系统」的决定）。
                .preferredColorScheme(.dark)
        }
    }
}
