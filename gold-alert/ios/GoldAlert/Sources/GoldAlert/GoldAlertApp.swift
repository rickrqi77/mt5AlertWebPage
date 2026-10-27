import SwiftUI

@main
struct GoldAlertApp: App {
    @StateObject private var model = AppViewModel()

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
