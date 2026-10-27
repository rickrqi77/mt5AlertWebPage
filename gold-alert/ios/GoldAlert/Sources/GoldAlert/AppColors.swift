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

    /// 强调文字色（ren 2026-10-28 定，后又改定深色为绿）：最终价、
    /// 左上角「提醒事项」与铃铛图标——深色模式绿色，浅色模式蓝色（系统蓝）。
    static let appAccentText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.3, green: 0.75, blue: 0.45, alpha: 1)
            : UIColor.systemBlue
    })

    /// 按钮底色（ren 2026-10-28 定）：保存按钮与触发按钮统一用它、配白字——
    /// 深色模式绿色，浅色模式蓝色（系统蓝）。
    static let appButton = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1)
            : UIColor.systemBlue
    })
}
