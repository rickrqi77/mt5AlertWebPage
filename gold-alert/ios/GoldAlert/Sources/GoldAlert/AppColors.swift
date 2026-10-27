import SwiftUI
import UIKit

extension Color {
    /// 品牌金：深色模式沿用原来的金色；浅色模式自动加深，
    /// 保证在白底上也看得清。跟随系统外观实时切换。
    ///（目前用于解锁按钮底色等少数保留金色的位置。）
    static let appGold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.83, green: 0.63, blue: 0.09, alpha: 1)
            : UIColor(red: 0.55, green: 0.40, blue: 0.0, alpha: 1)
    })

    /// 强调文字色：最终价、左上角「提醒事项」与铃铛图标。
    /// 原为深色绿/浅色蓝，ren 2026-10-28 改定：统一用蓝色系（系统蓝），
    /// 且画面已固定深色模式，此色在黑底上就是系统蓝。
    static let appAccentText = Color(uiColor: .systemBlue)

    /// 画面背景（ren 2026-10-28 定）：深色模式纯黑；浅色模式不用纯白，
    /// 亮度稍微压低一点点（0.93 的浅灰）。
    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor(white: 0.93, alpha: 1)
    })

    /// 按钮底色：保存按钮与提醒按钮统一用它、配白字。
    /// 原为深色绿/浅色蓝，ren 2026-10-28 改定：统一用蓝色系（系统蓝）。
    static let appButton = Color(uiColor: .systemBlue)
}
