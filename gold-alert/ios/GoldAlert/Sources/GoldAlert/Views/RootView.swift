import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        // 外层 GeometryReader 只为读系统给的安全区数值（见 body 末尾说明）。
        GeometryReader { proxy in
        ZStack {
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
        // 安全区自补（TestFlight 构建 11–15 实测教训）：云端 Xcode（iOS 26 SDK）
        // 打出的包在 iPhone 17 上系统安全区为 0——标题顶进状态栏、底部按钮
        // 被切、提醒面板按全屏高度算行距导致列表不能滚；同代码 xtool 构建
        // 正常。已拆开实际 IPA 与 xtool 包逐键核对：Info.plist 功能键已全部
        // 一致，差异只剩构建元数据，plist 不是病因；背景写法（并列/修饰）也
        // 两种都试过、均无效。故这里不再依赖系统安全区：读到上/下安全区
        // 为 0 时，按灵动岛机型的值（上 59 / 下 34）自己补齐；系统给值正常
        // 时（如 xtool 构建）不补、行为不变。背景不再 ignoresSafeArea，
        // 安全区外的上下两条由窗口底色（深色下同为纯黑）填充，视觉无差。
        .padding(.top, proxy.safeAreaInsets.top == 0 ? 59 : 0)
        .padding(.bottom, proxy.safeAreaInsets.bottom == 0 ? 34 : 0)
        .background(Color.appBackground)
        }
        .onAppear { model.onAppear() }
    }
}
