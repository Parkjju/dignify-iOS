import SwiftUI

struct MyPageView: View {
    @Environment(AppSession.self) private var appSession

    @State private var nickname = ""
    @State private var isEditingNick = false
    @State private var nickDraft = ""
    @State private var nickError: String?

    @State private var items: [API.HypeItem] = []
    @State private var nextCursor: Int?
    @State private var isLoading = true
    @State private var loadFailed = false

    @State private var showWithdrawAlert = false

    /// 마이페이지에는 최근 며칠만 미리보기로 노출하고, 나머지는 하입 기록 화면으로.
    private let previewDayLimit = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                hypeSection
                Divider().padding(.horizontal, 20).padding(.vertical, 4)
                settingsList
                Text("v1.0.0")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.border)
                    .padding(.vertical, 24)
            }
        }
        .background(DSColor.background)
        .navigationTitle("My Page")
        .task { await loadInitial() }
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
            } catch {
                nickname = previous
            }
        }
    }

    // MARK: - Hype preview

    @ViewBuilder
    private var hypeSection: some View {
        if isLoading && items.isEmpty {
            ProgressView().padding(.vertical, 40)
        } else if items.isEmpty {
            Text(loadFailed ? String(localized: "Couldn't load") : String(localized: "No hyped tracks yet"))
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.vertical, 40)
        } else {
            HypeCollection(items: $items,
                           maxGroups: previewDayLimit,
                           onReloadNeeded: { await loadInitial() })
            if dayCount > previewDayLimit || nextCursor != nil {
                NavigationLink { HypeHistoryView() } label: { moreRow }
                    .buttonStyle(.plain)
            }
        }
    }

    private var moreRow: some View {
        HStack {
            Text("See all hypes")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DSColor.brand)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.brand)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    /// 현재 로드된 하입이 걸쳐 있는 날짜 수 — 미리보기 초과 여부 판단용.
    private var dayCount: Int {
        Set(items.map { Calendar.current.startOfDay(for: $0.hypedAt) }).count
    }

    // MARK: - Settings

    private var settingsList: some View {
        VStack(spacing: 0) {
            NavigationLink { GenreSettingsView() } label: { settingsRow("Genre Settings") }
            NavigationLink { LegalView(type: .terms) } label: { settingsRow("Terms of Service") }
            NavigationLink { LegalView(type: .privacy) } label: { settingsRow("Privacy Policy") }
            Button { logout() } label: { settingsRow("Log Out") }
            Button { showWithdrawAlert = true } label: { settingsRow("Delete Account", destructive: true) }
        }
        .buttonStyle(.plain)
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

    private func loadInitial() async {
        async let profile = try? appSession.api.send(.myProfile, as: API.UserProfile.self)
        isLoading = true
        loadFailed = false
        do {
            let res = try await appSession.api.send(.myHypes(), as: API.HypeListResponse.self)
            items = res.items
            nextCursor = res.nextCursor
        } catch {
            loadFailed = true
        }
        isLoading = false
        if let name = await profile?.nickname { nickname = name }
    }
}

#Preview {
    NavigationStack {
        MyPageView()
            .environment(AppSession())
    }
}
