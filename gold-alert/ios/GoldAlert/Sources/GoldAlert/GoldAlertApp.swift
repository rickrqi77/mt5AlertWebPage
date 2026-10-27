import SwiftUI

@main
struct GoldAlertApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
            // 不再强制深色：跟随系统外观设定，浅色/深色自动切换
            //（各画面颜色已改用自适应颜色，ren 2026-10-28 要求）。
        }
    }
}
