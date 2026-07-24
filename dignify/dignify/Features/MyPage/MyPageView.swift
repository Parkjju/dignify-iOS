import SwiftUI

struct MyPageView: View {
    @Environment(AppSession.self) private var appSession

    @State private var nickname = ""
    @State private var isEditingNick = false
    @State private var nickDraft = ""
    @State private var nickError: String?

    @State private var showWithdrawAlert = false
    @State private var showTutorial = false
    @State private var showWhatsNew = false
    @State private var legalDoc: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                diggingProfileEntry
                Divider().padding(.horizontal, 20).padding(.vertical, 4)
                settingsList
                Text("v1.0.3")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.border)
                    .padding(.vertical, 24)
            }
        }
        .background(DSColor.background)
        .navigationTitle("My Page")
        .task { await loadProfile() }
    }

    // MARK: - Profile

    private var profileHeader: some View {
        VStack {
            if isEditingNick {
                TextField("Nickname", text: $nickDraft)
                    .multilineTextAlignment(.center)
                    .font(DSTypography.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 180)
                    .submitLabel(.done)
                    .onSubmit { commitNickname() }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DSColor.brand).frame(height: 2).offset(y: 6)
                    }
                if let nickError {
                    Text(nickError)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.destructive)
                        .padding(.top, 12)
                }
            } else {
                Button {
                    nickDraft = nickname
                    isEditingNick = true
                } label: {
                    HStack(spacing: 6) {
                        Text(nickname.isEmpty ? " " : nickname)
                            .font(DSTypography.headline)
                            .foregroundStyle(DSColor.textPrimary)
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private func commitNickname() {
        let new = nickDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if new == nickname { isEditingNick = false; nickError = nil; return }
        // 백엔드 검증(NicknameUpdateRequest @Pattern)과 동일 규칙으로 미리 막는다.
        guard new.range(of: "^[a-zA-Z0-9_가-힣]{1,20}$", options: .regularExpression) != nil else {
            nickError = String(localized: "Letters, numbers, and _ only (1–20 characters)")
            return                          // 편집 모드 유지.
        }
        nickError = nil
        isEditingNick = false
        let previous = nickname
        nickname = new                      // 낙관적 반영, 실패 시 롤백.
        Task {
            do {
                let res = try await appSession.api.send(.updateNickname(new), as: API.NicknameResponse.self)
                nickname = res.nickname
            } catch APIError.server(_, _, let status) where status == 409 {
                reopenNickEdit(previous: previous, attempted: new,
                               error: String(localized: "This nickname is already in use."))
            } catch {
                reopenNickEdit(previous: previous, attempted: new,
                               error: String(localized: "Couldn't update. Please try again."))
            }
        }
    }

    /// 닉네임 변경 실패 시 롤백하고 편집 모드를 다시 열어 오류를 보여준다(조용한 롤백 방지).
    private func reopenNickEdit(previous: String, attempted: String, error: String) {
        nickname = previous
        nickDraft = attempted
        nickError = error
        isEditingNick = true
    }

    // MARK: - Digging Profile entry

    private var diggingProfileEntry: some View {
        NavigationLink { DiggingProfileView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(DSColor.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Digging Profile")
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textPrimary)
                    Text("Your taste, typed")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.border)
            }
            .padding(12)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings

    private var settingsList: some View {
        VStack(spacing: 0) {
            NavigationLink { GenreSettingsView() } label: { settingsRow("Genre Settings") }
            NavigationLink { ArtistRequestHistoryView() } label: { settingsRow("Artist Requests") }
            Button { showTutorial = true } label: { settingsRow("How to Use") }
            Button { showWhatsNew = true } label: { settingsRow("What's New") }
            Button { legalDoc = .terms } label: { settingsRow("Terms of Service") }
            Button { legalDoc = .privacy } label: { settingsRow("Privacy Policy") }
            Button { logout() } label: { settingsRow("Log Out") }
            Button { showWithdrawAlert = true } label: { settingsRow("Delete Account", destructive: true) }
        }
        .buttonStyle(.plain)
        .sheet(item: $legalDoc) { SafariView(url: $0.url) }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView { showTutorial = false }
        }
        // 같은 뷰에 .sheet 두 개(legalDoc)는 충돌 → 별도 노드에 부착.
        .background {
            Color.clear.sheet(isPresented: $showWhatsNew) {
                WhatsNewView()
            }
        }
        .alert("Delete account?", isPresented: $showWithdrawAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { withdraw() }
        } message: {
            Text("All your data, including hypes and genres, will be deleted permanently.")
        }
    }

    private func settingsRow(_ label: LocalizedStringKey, destructive: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(destructive ? DSColor.destructive : DSColor.textPrimary)
            Spacer()
            if !destructive {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.border)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func logout() {
        Task { await appSession.logout() }
    }

    private func withdraw() {
        Task { try? await appSession.withdraw() }
    }

    // MARK: - Loading

    /// 하입 브라우징은 Digging Profile로 이관됨 — 마이페이지는 닉네임만 복원한다.
    private func loadProfile() async {
        if let profile = try? await appSession.api.send(.myProfile, as: API.UserProfile.self) {
            nickname = profile.nickname
        }
    }
}

#Preview {
    NavigationStack {
        MyPageView()
            .environment(AppSession())
    }
}
