import SwiftUI
import UIKit

enum AppTheme {
    static let backgroundTop = Color(uiColor: .systemGroupedBackground)
    static let backgroundBottom = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfacePrimary = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceSecondary = Color(uiColor: .tertiarySystemGroupedBackground)
    static let divider = Color(uiColor: .separator).opacity(0.28)
    static let handle = Color(uiColor: .quaternaryLabel).opacity(0.5)
    static let textPrimary = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(hex: 0xF5F5F5)
        }
        return UIColor(hex: 0x2F4F4F)
    })
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    static let controlStrong = Color(uiColor: .label)
    static let inactiveControl = Color(uiColor: .quaternaryLabel).opacity(0.22)
    static let elevatedShadow = Color.black.opacity(0.18)

    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [
                backgroundTop,
                backgroundBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
