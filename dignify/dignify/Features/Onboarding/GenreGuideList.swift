import SwiftUI

/// 장르 목록에 한 줄 설명을 붙인 형태. 마이페이지 장르 설정의 "설명 보기"가 쓴다.
/// 온보딩은 퀴즈가 장르를 골라주므로 이 목록을 쓰지 않는다 — 여긴 이미 앱을 쓰는 사람이
/// 직접 고르는 자리라, 칩만으론 부족할 때 설명을 펼쳐 보는 용도.
struct GenreGuideList: View {
    let genres: [Genre]
    @Binding var selected: Set<Genre>
    var maxPicks: Int = 3

    var body: some View {
        VStack(spacing: 8) {
            ForEach(genres) { row($0) }
        }
    }

    private func row(_ genre: Genre) -> some View {
        let isSelected = selected.contains(genre)
        let isDisabled = !isSelected && selected.count >= maxPicks

        return Button {
            toggle(genre)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.name)
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textPrimary)
                    // nameEn은 백엔드 배포 전 nil — en 로케일에선 name이 곧 원문이라 폴백이 먹힌다.
                    if let blurb = GenreGuide.blurb(for: genre.nameEn ?? genre.name) {
                        Text(blurb)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? DSColor.brand : DSColor.border)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .fill(isSelected ? DSColor.brandLight : DSColor.surface)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private func toggle(_ genre: Genre) {
        if selected.contains(genre) {
            selected.remove(genre)
        } else if selected.count < maxPicks {
            selected.insert(genre)
        }
    }
}
