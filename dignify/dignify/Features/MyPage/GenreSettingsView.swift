import SwiftUI

/// 마이페이지 장르 설정 — 현재 선택을 프리로드하고 최대 3개까지 편집해 저장한다.
struct GenreSettingsView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var genres: [Genre] = []
    @State private var selected: Set<Genre> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Pick up to 3")
                        .font(.system(size: 14))
                        .foregroundStyle(DSColor.textTertiary)

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
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
    }

    private func load() async {
        async let genresResult = try? appSession.fetchGenres()
        async let profileResult = try? appSession.api.send(.myProfile, as: API.UserProfile.self)
        let all = await genresResult ?? []
        let currentNames = Set((await profileResult)?.genres.map(\.genreName) ?? [])
        genres = all
        selected = Set(all.filter { currentNames.contains($0.name) })
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
                try await appSession.api.send(.updateGenres(ids: selected.map(\.id)))
                dismiss()
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
            }
        }
    }
}
