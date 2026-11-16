import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ZStack {
            // 背景色不在这里并列放（改用下方 background 修饰）：并列的
            // ignoresSafeArea 会连内容的安全区一起吃掉（见 body 末尾说明）。
            if model.isUnlocked {
                MainView()
            } else {
                AuthView()
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(model.toastIsError
                                  ? Color(red: 0.75, green: 0.22, blue: 0.17)
                                  : Color.black)
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: model.toast)
            }
        }
        // 背景色铺满全屏（含状态栏与 Home 指示条后面）只用 background 修饰实现：
        // 背景里的 ignoresSafeArea 只作用于背景本身。若把背景色作为 ZStack 的
        // 并列子视图加 ignoresSafeArea，iOS 26 SDK 构建下整个 ZStack 的安全区
        // 会被一起吃掉——实测症状：标题顶进状态栏、底部按钮被屏幕切掉、
        // 提醒面板按全屏高度算行距导致列表不能滚（TestFlight 构建 11/13 均中招，
        // 同代码的 xtool 构建正常）。内容留在安全区内，背景照旧全屏黑。
        .background { Color.appBackground.ignoresSafeArea() }
        .onAppear { model.onAppear() }
    }
}
