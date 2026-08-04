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
    static let divider = Color(hex: 0xF3F4F6)
    static let destructive = Color(hex: 0xEF4444)

    // MARK: Picks (다크 지면)
    //
    // 앱은 라이트 고정이지만 Picks만 예외다. 흰 배경 위 #F3F4F6 카드는 대비가 거의 없어
    // 아트워크가 떠 있기만 하고 지면이 밋밋했다. 어둡게 깔면 커버가 유일한 색이 되고,
    // 카드 탭 → 검은 재생 화면 전환도 톤이 끊기지 않는다.
    static let pickBackground = Color(hex: 0x141420)
    static let pickSurface = Color(hex: 0x1E1E2A)
    /// 다크 위에서 `brand`(#4B3FD8)는 배경에 묻힌다. 같은 색상각을 밝기만 올려 쓴다.
    static let pickAccent = Color(hex: 0x8F86FF)
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
