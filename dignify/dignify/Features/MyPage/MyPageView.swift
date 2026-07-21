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
    @State private var showTutorial = false
    @State private var showWhatsNew = false
    @State private var legalDoc: LegalDocument?

    /// 마이페이지에는 최근 며칠만 미리보기로 노출하고, 나머지는 하입 기록 화면으로.
    private let previewDayLimit = 5
    /// 미리보기에서 한 날짜당 가로로 보여줄 최대 트랙 수(초과분은 See all에서).
    private let perDayPreviewLimit = 10
    @State private var showAllHypes = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                hypeSection
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
        .task { await loadInitial() }
        .navigationDestination(isPresented: $showAllHypes) { HypeHistoryView() }
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
                           perDayLimit: perDayPreviewLimit,
                           onReloadNeeded: { await loadInitial() },
                           onSeeAll: hasMore ? { showAllHypes = true } : nil)
            if hasMore {
                Button { showAllHypes = true } label: { moreRow }
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

    /// 미리보기 밖에 더 볼 하입이 있는가 — 날짜 초과 / 다음 페이지 존재 / 특정 날짜 트랙 초과.
    private var hasMore: Bool {
        if nextCursor != nil { return true }
        let byDay = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.hypedAt) }
        if byDay.count > previewDayLimit { return true }
        return byDay.values.contains { $0.count > perDayPreviewLimit }
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

    /// 백엔드는 하입을 페이지(10개)로 주므로, 최근 previewDayLimit(5)일치가 각각 완결될
    /// 때까지 이어 받는다. 하루에 하입이 몰려도 그 날짜 미리보기가 잘리지 않게 한다.
    /// ponytail: 페이지네이션이 날짜 단위가 아니라, 하루 하입이 아주 많으면 그날을 다 받아야
    /// 다음 날로 넘어간다. maxPages로 상한을 둬 병적 로드를 막고, 나머지는 See all이 담당.
    private func loadInitial() async {
        async let profile = try? appSession.api.send(.myProfile, as: API.UserProfile.self)
        isLoading = true
        loadFailed = false
        do {
            var collected: [API.HypeItem] = []
            var cursor: Int? = nil
            let maxPages = 8
            for _ in 0..<maxPages {
                let res = try await appSession.api.send(.myHypes(cursor: cursor), as: API.HypeListResponse.self)
                collected.append(contentsOf: res.items)
                cursor = res.nextCursor
                let days = Set(collected.map { Calendar.current.startOfDay(for: $0.hypedAt) }).count
                // days > previewDayLimit 이면 6번째 날에 진입 → 앞 5일치는 완결됨.
                if cursor == nil || days > previewDayLimit { break }
            }
            items = collected
            nextCursor = cursor
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
