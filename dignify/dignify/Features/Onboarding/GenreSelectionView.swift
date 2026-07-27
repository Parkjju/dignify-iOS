//
//  GenreSelectionView.swift
//  dignify
//
//  Created by 박경준 on 6/30/26.
//

import SwiftUI

/// 온보딩 장르 선택 플로우.
///
///     튜토리얼 → 취향 테스트 할래? ┬─ 예 → 문항 11개 → 결과(유형 + 추천 장르) → 완료
///                                └─ 아니오 → 칩 목록 → 완료
///
/// 어느 단계에서든 Skip은 칩 목록으로 빠진다. 테스트를 강제하지 않는 게 전제라
/// 문항 수를 늘려도 이탈 위험이 안 커진다.
struct GenreSelectionView: View {
    enum Step: Equatable {
        case tutorial
        case intro
        case quiz
        case result(DiggingType)
        case chips
    }

    /// 프리뷰에서 네트워크 대신 쓸 고정 데이터. 앱 경로에선 항상 nil.
    var previewGenres: [Genre]?

    @Environment(AppSession.self) private var appSession
    @State private var step: Step
    @State private var genres: [Genre] = []
    @State private var selectedGenres: Set<Genre> = []
    @State private var recommended: [Genre] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let maxPicks = 3

    init(previewGenres: [Genre]? = nil, initialStep: Step = .tutorial) {
        self.previewGenres = previewGenres
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        Group {
            switch step {
            case .tutorial:
                // 피드 조작을 먼저 익히게 한다. 장르 목록은 이 동안 백그라운드로 받는다.
                TutorialView { step = .intro }
            case .intro:
                introView
            case .quiz:
                TasteQuizView(onFinish: finishQuiz, onSkip: { step = .chips })
            case .result(let type):
                TasteResultView(
                    type: type,
                    recommended: recommended,
                    selected: $selectedGenres,
                    isBusy: isSubmitting,
                    errorMessage: errorMessage,
                    onStart: submit,
                    onEditManually: { step = .chips }
                )
            case .chips:
                chipsView
            }
        }
        .background(DSColor.background)
        .task { await loadGenres() }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                // verbatim이 아니면 이모지가 번역 대상 키로 카탈로그에 실린다.
                Text(verbatim: "🎧").font(.system(size: 56))
                Text("Not sure what to pick?")
                    .font(DSTypography.title1)
                    .tracking(-0.48)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Answer a few quick questions and we'll figure out your type — and which genres to start you on.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }
            Spacer()
            VStack(spacing: 4) {
                Button { step = .quiz } label: {
                    Text("Take the taste test")
                }
                .buttonStyle(DSPrimaryButtonStyle())

                Button { step = .chips } label: {
                    Text("Skip and pick genres")
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Chips

    private var chipsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What music do you like?")
                            .font(DSTypography.title1)
                            .tracking(-0.48)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("Pick up to 3")
                            .font(.system(size: 14))
                            .foregroundStyle(DSColor.textTertiary)
                    }

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if loadFailed {
                        retryView
                    } else {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(genres) { genre in
                                let isSelected = selectedGenres.contains(genre)
                                let isDisabled = !isSelected && selectedGenres.count >= maxPicks
                                DSGenreChip(title: genre.name, isSelected: isSelected, isDisabled: isDisabled) {
                                    toggle(genre)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }

            bottomBar
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if !selectedGenres.isEmpty {
                Text("\(selectedGenres.map(\.name).sorted().joined(separator: ", ")) selected")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
                    .multilineTextAlignment(.center)
            }

            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Done")
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background {
            Rectangle()
                .fill(DSColor.background)
                .overlay(alignment: .top) {
                    Rectangle().fill(DSColor.divider).frame(height: 1)
                }
        }
    }

    private var retryView: some View {
        VStack(spacing: 12) {
            Text("Couldn't load")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            Button("Try again") { Task { await loadGenres() } }
                .foregroundStyle(DSColor.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    /// 퀴즈 결과를 서버 장르 목록에 매칭한다. 추천 장르는 그대로 선택 상태로 넘어가고,
    /// 결과 화면에서 체크를 풀 수 있다.
    private func finishQuiz(_ answers: [Int]) {
        let result = TasteQuiz.result(answers: answers)
        recommended = result.genreNames.compactMap { name in
            genres.first { ($0.nameEn ?? $0.name) == name }
        }
        selectedGenres = Set(recommended)
        // 예상 유형을 남겨 두면 프로필이 잠긴 동안에도 유형 자리를 채울 수 있다.
        DiggingType.setPredicted(result.type)
        step = .result(result.type)
    }

    private func loadGenres() async {
        if let previewGenres {
            genres = previewGenres
            isLoading = false
            return
        }
        // 스텝을 옮길 때 .task가 다시 돌더라도 재요청하지 않는다(로딩 깜빡임 방지).
        // 실패 시엔 genres가 비어 있어 Try again은 그대로 동작한다.
        guard genres.isEmpty else { return }
        isLoading = true
        loadFailed = false
        do {
            genres = try await appSession.fetchGenres()
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func toggle(_ genre: Genre) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else if selectedGenres.count < maxPicks {
            selectedGenres.insert(genre)
        }
    }

    /// 선택 장르를 서버에 저장하고 온보딩 완료 처리 후 signedIn으로 전환한다.
    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await appSession.api.send(.updateGenres(ids: selectedGenres.map(\.id)))
                try await appSession.api.send(.completeOnboarding)
                // MainTabView가 이 플래그로 "방금 가입한 유저"를 알아본다(What's New 오발동 방지).
                // 튜토리얼은 이 플로우 앞단에서 이미 봤다.
                UserDefaults.standard.set(true, forKey: "didJustOnboard")
                appSession.authState = .signedIn
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
            }
        }
    }
}

#Preview("1. Intro") {
    GenreSelectionView(previewGenres: Genre.previewList, initialStep: .intro)
        .environment(AppSession())
}

#Preview("2. Quiz") {
    GenreSelectionView(previewGenres: Genre.previewList, initialStep: .quiz)
        .environment(AppSession())
}

#Preview("3. Chips") {
    GenreSelectionView(previewGenres: Genre.previewList, initialStep: .chips)
        .environment(AppSession())
}
