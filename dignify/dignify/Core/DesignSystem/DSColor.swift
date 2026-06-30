import SwiftUI

enum DSColor {
    static let brand = Color(hex: 0x4B3FD8)
    static let brandLight = Color(hex: 0xEEF0FF)
    static let background = Color(hex: 0xFFFFFF)
    static let surface = Color(hex: 0xF3F4F6)
    static let textPrimary = Color(hex: 0x111827)
    static let textSecondary = Color(hex: 0x6B7280)
    static let textTertiary = Color(hex: 0x9CA3AF)
    static let border = Color(hex: 0xD1D5DB)
    static let borderLight = Color(hex: 0xE5E7EB)
    static let destructive = Color(hex: 0xEF4444)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
