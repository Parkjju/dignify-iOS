//
//  GenreSelectionView.swift
//  dignify
//
//  Created by 박경준 on 6/30/26.
//

import SwiftUI

struct GenreSelectionView: View {
    @Environment(AppSession.self) private var appSession
    @State private var genres: [Genre] = []
    @State private var selectedGenres: Set<Genre> = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("어떤 음악을 좋아하세요?")
                            .font(DSTypography.title1)
                            .tracking(-0.48)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("최대 3개까지 선택할 수 있어요")
                            .font(.system(size: 14))
                            .foregroundStyle(DSColor.textTertiary)
                    }

                    if genres.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(genres) { genre in
                                let isSelected = selectedGenres.contains(genre)
                                let isDisabled = !isSelected && selectedGenres.count >= 3
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

            VStack(spacing: 12) {
                if !selectedGenres.isEmpty {
                    Text("\(selectedGenres.map(\.name).sorted().joined(separator: ", ")) 선택됨")
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
                        Text("완료")
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
                        Rectangle()
                            .fill(DSColor.divider)
                            .frame(height: 1)
                    }
            }
        }
        .background(DSColor.background)
        .task { genres = (try? await appSession.fetchGenres()) ?? [] }
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
                appSession.authState = .signedIn
            } catch {
                errorMessage = "저장에 실패했어요. 다시 시도해 주세요."
            }
        }
    }

    private func toggle(_ genre: Genre) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else if selectedGenres.count < 3 {
            selectedGenres.insert(genre)
        }
    }
}

#Preview {
    GenreSelectionView()
        .environment(AppSession())
}
