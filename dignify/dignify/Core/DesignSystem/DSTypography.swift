import SwiftUI

enum DSTypography {
    static let display = Font.system(size: 40, weight: .bold, design: .default)
    static let title1 = Font.system(size: 24, weight: .bold, design: .default)
    static let title2 = Font.system(size: 18, weight: .bold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    /// 팝업·시트 설명, 보조 텍스트 버튼.
    static let bodySmall = Font.system(size: 14, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .medium, design: .default)
    /// 보조 버튼·칩, 토스트 제목.
    static let callout = Font.system(size: 14, weight: .medium, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    static let micro = Font.system(size: 10.5, weight: .regular, design: .default)

    static let title = title1
}
