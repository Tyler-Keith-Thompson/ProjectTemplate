import SwiftUI
import UIKit

extension Color {
    /// Text that carries a screen's content.
    public static let textPrimary = Color(light: 0x1D1C1D, dark: 0xD1D2D3)

    // A dynamic UIColor resolves against each trait collection, so one token follows light and
    // dark mode wherever it is drawn.
    fileprivate init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
