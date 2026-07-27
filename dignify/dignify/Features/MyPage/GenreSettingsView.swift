import SwiftUI

/// 마이페이지 장르 설정 — 현재 선택을 프리로드하고 최대 3개까지 편집해 저장한다.
/// 기본은 칩 목록(이미 앱을 쓰는 사람이라 빠른 재선택이 목적), 장르 이름만으론 헷갈릴 때
/// "설명 보기"로 한 줄 설명이 붙은 목록을 펼칠 수 있다.
struct GenreSettingsView: View {
    /// 프리뷰용 고정 데이터. 앱 경로에선 항상 nil (GenreSelectionView와 같은 패턴).
    var previewGenres: [Genre]?

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var genres: [Genre] = []
    @State private var selected: Set<Genre> = []
    @State private var showGuide = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// 취향 테스트 재검사. nil이면 문항 단계, 값이 있으면 결과 단계.
    /// 결과는 `retakeSelection`에만 담고 "이 장르로 바꾸기"를 눌러야 `selected`로 넘어간다 —
    /// 곧바로 덮어쓰면 결과를 보고 무를 방법이 없어진다.
    /// 넘어온 뒤에도 저장은 Save 버튼 하나로만 일어난다.
    @State private var isRetaking = false
    @State private var retakeType: DiggingType?
    @State private var retakeGenres: [Genre] = []
    @State private var retakeSelection: Set<Genre> = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Pick up to 3")
                            .font(.system(size: 14))
                            .foregroundStyle(DSColor.textTertiary)
                        Spacer(minLength: 12)
                        if !isLoading {
                            Button(guideToggleLabel) { showGuide.toggle() }
                                .font(DSTypography.bodyMedium)
                                .foregroundStyle(DSColor.brand)
                        }
                    }

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if showGuide {
                        GenreGuideList(genres: genres, selected: $selected)
                    } else {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(genres) { genre in
                                let isSelected = selected.contains(genre)
                                let isDisabled = !isSelected && selected.count >= 3
                                DSGenreChip(title: genre.name, isSelected: isSelected, isDisabled: isDisabled) {
                                    toggle(genre)
                                }
                            }
                        }
                    }

                    if !isLoading {
                        Button {
                            retakeType = nil
                            isRetaking = true
                        } label: {
                            Text("Retake the taste test")
                        }
                        .buttonStyle(DSOutlineButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.destructive)
                }
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().tint(.white) } else { Text("Save") }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(isSaving || selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(DSColor.background)
        .navigationTitle("Genre Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $isRetaking) { retakeFlow }
    }

    /// 문항 → 결과. 결과에서 적용하면 선택만 갈아끼우고 닫힌다(저장은 Save 버튼).
    @ViewBuilder
    private var retakeFlow: some View {
        if let type = retakeType {
            TasteResultView(
                type: type,
                recommended: retakeGenres,
                selected: $retakeSelection,
                primaryTitle: "Use these genres",
                secondaryTitle: "Keep what I had",
                onStart: {
                    selected = retakeSelection
                    isRetaking = false
                },
                onEditManually: { isRetaking = false }
            )
        } else {
            TasteQuizView(
                source: "retake",
                onFinish: showRetakeResult,
                onSkip: { isRetaking = false }
            )
        }
    }

    private func showRetakeResult(_ answers: [Int]) {
        let result = TasteQuiz.result(answers: answers)
        retakeGenres = result.genreNames.compactMap { name in
            genres.first { ($0.nameEn ?? $0.name) == name }
        }
        retakeSelection = Set(retakeGenres)
        // 유형은 무르지 않는다 — 방금 답한 내용이 최신이고, 확정 유형이 생기면 어차피 무시된다.
        DiggingType.setPredicted(result.type)
        retakeType = result.type
    }

    /// 삼항 결과를 Button에 바로 넘기면 LocalizedStringKey 대신 String 오버로드가 잡혀
    /// 번역을 안 타고 영어로 박힌다(ProfileShareCardView에도 같은 함정 주석이 있다).
    private var guideToggleLabel: LocalizedStringKey {
        showGuide ? "Hide guide" : "Show guide"
    }

    private func load() async {
        if let previewGenres {
            genres = previewGenres
            isLoading = false
            return
        }
        async let genresResult = try? appSession.fetchGenres()
        async let profileResult = try? appSession.api.send(.myProfile, as: API.UserProfile.self)
        let all = await genresResult ?? []
        // id로 대조한다. 이름은 서버가 로케일별로 다르게 내려주는 표시용 값이라,
        // /genres와 /users/me의 문자열이 어긋나면 선택이 조용히 사라진다.
        let currentIds = Set((await profileResult)?.genres.map(\.genreId) ?? [])
        genres = all
        selected = Set(all.filter { currentIds.contains($0.id) })
        isLoading = false
    }

    private func toggle(_ genre: Genre) {
        if selected.contains(genre) {
            selected.remove(genre)
        } else if selected.count < 3 {
            selected.insert(genre)
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await appSession.updateGenres(ids: selected.map(\.id))
                dismiss()
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
            }
        }
    }
}

#Preview("Genre settings") {
    NavigationStack {
        GenreSettingsView(previewGenres: Genre.previewList)
            .environment(AppSession())
    }
}
