import SwiftUI
import WidgetKit

@main
struct GoldAlertWatchApp: App {
    @StateObject private var model = WatchModel()

    init() {
        // 每次打开表端 app 就强制刷新一次复杂功能时间线：表盘上的
        // 占位灰条在扩展更新后可能不自动失效（ren 构建 19–21 实测，
        // 拆包核对扩展注册与代码均无误），靠这个调用把表盘渲染
        // 拉回最新内容（构建 23）。
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}
