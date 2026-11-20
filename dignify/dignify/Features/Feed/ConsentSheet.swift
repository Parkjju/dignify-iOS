import SwiftUI

/// 좋아요 시점 신곡 알림 제안(Components › ConsentSheet, 플로우 P05).
/// 피드에서 곡을 좋아요하고 다음 곡으로 넘어간 직후 뜬다. 버튼으로만 닫힌다(띄우는 쪽이 `interactiveDismissDisabled`).
struct ConsentSheet: View {
    let artist: String
    /// 알림 미리보기의 아이콘 자리. 없으면 dignify 마크.
    let artworkURL: URL?
    let onAccept: () -> Void
    let onMute: () -> Void
    /// 우측 상단 X. 닫기만 한다(QA #6).
    let onClose: () -> Void

    /// ponytail: 콘텐츠가 고정이라 높이를 계산해 상수로 준다(실측 detent는 `.large`로 눌러앉는다).
    /// 24 + 제목 58 + 12 + 설명 21 + 24 + 미리보기 120 + 10 + 동의 문구 16 + 8 + 버튼 50 + 12 + 34 + 여유 13.
    /// 글자 크기를 키우면 아래가 잘릴 수 있다 — 그때는 실측으로.
    static let height: CGFloat = 402

    /// 제목 두 줄. 첫 줄(「(아티스트) 신곡」, brand)이 한 줄에 안 들어가면 「좋아요한 아티스트의 신곡」으로 바꾼다(QA #5).
    private var titleLines: (artist: String, generic: String, rest: String) {
        let full = String(localized: "New music from \(artist)\nBe the first to know!").split(separator: "\n", maxSplits: 1)
        let generic = String(localized: "New music from artists you like\nBe the first to know!").split(separator: "\n", maxSplits: 1)
        return (String(full.first ?? ""), String(generic.first ?? ""), String(full.dropFirst().first ?? ""))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                VStack(spacing: 24 * 0.2) {
                    // 좌우 52 = X 버튼(44 + 8)을 비켜 가운데 정렬을 유지한다.
                    ViewThatFits(in: .horizontal) {
                        Text(titleLines.artist).lineLimit(1)
                        Text(titleLines.generic).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(DSColor.brand)
                    .padding(.horizontal, 36)
                    Text(titleLines.rest)
                        .foregroundStyle(DSColor.textPrimary)
                }
                .font(DSTypography.title1)
                Text("To get updates, turn on **Settings > Notifications**.")
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineSpacing(14 * 0.5)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 24)

            NotificationPreview(artworkURL: artworkURL)
                .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Tapping Notify me means you agree to receive advertising information.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                Button(action: onAccept) {
                    Text("Notify me")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium))
                }
                .buttonStyle(.plain)
                Button(action: onMute) {
                    Text("Don't show for a week")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DSColor.background)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }
}

/// 알림 미리보기 그림 343×120(Figma `image_nps` 실측). 기기 윗부분 + 알림 카드 두 장, 아래는 흰색으로 흐려진다.
private struct NotificationPreview: View {
    let artworkURL: URL?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 기기 틀: 왼쪽 16, 폭 311, 위 모서리 30, 테두리 6. 아래는 그림 밖으로 이어진다.
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(DSColor.surface)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                        .strokeBorder(DSColor.borderLight, lineWidth: 6)
                )
                .frame(width: 311, height: 140)
                .offset(x: 16)
            Capsule()
                .fill(DSColor.borderLight)
                .frame(width: 32, height: 8)
                .offset(x: 16 + (311 - 32) / 2, y: 11)
            // 뒤 카드 → 앞 카드
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.7))
                .frame(width: 262, height: 59)
                .offset(x: 39, y: 40)
            RoundedRectangle(cornerRadius: 18)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .frame(width: 280, height: 63)
                .offset(x: 31, y: 27)
            icon
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .offset(x: 44, y: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("(Ad) New music from an artist you'll love 🎧")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("We lined up some matching tracks too 💗")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .lineLimit(1)
            .frame(width: 280 - (85 - 31) - 12, alignment: .leading)
            .offset(x: 85, y: 43)
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                .frame(width: 343, height: 21)
                .offset(y: 120 - 21)
        }
        .frame(width: 343, height: 120, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let artworkURL {
            RemoteImage(url: artworkURL) { DSColor.surface }
                .scaledToFill()
        } else {
            DSBrandMark(size: 34)
        }
    }
}

#Preview {
    ConsentSheet(artist: "혁오", artworkURL: nil, onAccept: {}, onMute: {}, onClose: {})
        .frame(height: ConsentSheet.height)
}
