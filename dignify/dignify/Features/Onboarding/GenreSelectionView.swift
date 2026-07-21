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
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
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
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if loadFailed {
                        retryView
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
                        Rectangle()
                            .fill(DSColor.divider)
                            .frame(height: 1)
                    }
            }
        }
        .background(DSColor.background)
        .task { await loadGenres() }
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

    private func loadGenres() async {
        isLoading = true
        loadFailed = false
        do {
            genres = try await appSession.fetchGenres()
        } catch {
            loadFailed = true
        }
        isLoading = false
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
                // 신규 온보딩 유저에게만 튜토리얼을 띄운다(MainTabView가 이 플래그로 게이트).
                UserDefaults.standard.set(true, forKey: "pendingTutorial")
                appSession.authState = .signedIn
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
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
