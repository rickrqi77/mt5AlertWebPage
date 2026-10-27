import SwiftUI
import UIKit

extension Color {
    /// 品牌金：深色模式沿用原来的金色；浅色模式自动加深，
    /// 保证在白底上（标题、最终价）也看得清。跟随系统外观实时切换。
    static let appGold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.83, green: 0.63, blue: 0.09, alpha: 1)
            : UIColor(red: 0.55, green: 0.40, blue: 0.0, alpha: 1)
    })
}
