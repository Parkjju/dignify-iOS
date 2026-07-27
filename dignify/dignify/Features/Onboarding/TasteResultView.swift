import SwiftUI

/// 취향 테스트 결과 — 유형 + 추천 장르(프리셀렉트).
///
/// 유형을 "예상"이라고 못 박는다. 퀴즈 11문항은 얇은 데이터라 정체성을 확정할 근거가 못 되고,
/// 확정은 실제 청취·하입에서 나온다(`DiggingStats.type`). "예상 → 확정"의 어긋남 자체가
/// 나중에 보여줄 콘텐츠라서, 여기서 단정하면 그 서사를 잃는다.
struct TasteResultView: View {
    let type: DiggingType
    let recommended: [Genre]
    @Binding var selected: Set<Genre>
    var isBusy: Bool = false
    var errorMessage: String?
    /// 주 버튼 문구 — 온보딩은 "디깅 시작", 설정에서 재검사할 땐 "이 장르로 바꾸기".
    var primaryTitle: LocalizedStringKey = "Start digging"
    /// nil이면 보조 버튼을 숨긴다(설정에서는 이미 장르 화면 위라 갈 곳이 없다).
    var secondaryTitle: LocalizedStringKey? = "Pick genres myself"
    var onStart: () -> Void
    var onEditManually: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    typeCard
                    if recommended.isEmpty {
                        Text("Couldn't load genres — pick them yourself on the next screen.")
                            .font(DSTypography.body)
                            .foregroundStyle(DSColor.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        genreSection
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 28)
            }

            bottomBar
        }
        .background(DSColor.background)
    }

    // MARK: - Type

    private var typeCard: some View {
        VStack(spacing: 12) {
            Text(type.emoji)
                .font(.system(size: 56))

            VStack(spacing: 6) {
                Text("Your likely type")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                Text(type.name)
                    .font(DSTypography.display)
                    .tracking(-1)
                    .foregroundStyle(DSColor.brand)
                    .multilineTextAlignment(.center)
                Text(type.blurb)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(type.traits, id: \.self) { trait in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(DSColor.brand)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(trait)
                            .font(DSTypography.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(DSColor.brandLight, in: RoundedRectangle(cornerRadius: DSRadius.medium))

            Text("We'll confirm this once you've actually dug around a bit.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Genres

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sounds like your kind of thing")
                    .font(DSTypography.title2)
                    .foregroundStyle(DSColor.textPrimary)
                Text("Uncheck anything that's off.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }

            VStack(spacing: 8) {
                ForEach(recommended) { genreRow($0) }
            }
        }
        .padding(.horizontal, 24)
    }

    private func genreRow(_ genre: Genre) -> some View {
        let isPicked = selected.contains(genre)

        return Button {
            if isPicked { selected.remove(genre) } else { selected.insert(genre) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.name)
                        .font(DSTypography.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    if let blurb = GenreGuide.blurb(for: genre.nameEn ?? genre.name) {
                        Text(blurb)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isPicked ? DSColor.brand : DSColor.border)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .fill(isPicked ? DSColor.brandLight : DSColor.surface)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
                    .multilineTextAlignment(.center)
            }

            if recommended.isEmpty {
                // 추천이 하나도 안 잡힌 상태에서 Start를 비활성으로 두면 주 버튼이 죽는다.
                // 유형은 유효하니(장르명과 무관한 유형 문항에서 나옴) 장르만 고르러 보낸다.
                Button(action: onEditManually) {
                    Text("Choose your genres")
                }
                .buttonStyle(DSPrimaryButtonStyle())
            } else {
                Button(action: onStart) {
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryTitle)
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(isBusy || selected.isEmpty)

                if let secondaryTitle {
                    Button(secondaryTitle, action: onEditManually)
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background {
            Rectangle()
                .fill(DSColor.background)
                .overlay(alignment: .top) {
                    Rectangle().fill(DSColor.divider).frame(height: 1)
                }
        }
    }
}

#Preview {
    @Previewable @State var selected: Set<Genre> = Set(Genre.previewList.prefix(3))
    TasteResultView(
        type: .omnivore,
        recommended: Array(Genre.previewList.prefix(3)),
        selected: $selected,
        onStart: {},
        onEditManually: {}
    )
}
