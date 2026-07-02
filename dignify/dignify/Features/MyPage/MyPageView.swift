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
                TextField("닉네임", text: $nickDraft)
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
            nickError = "영문·한글·숫자·_ 1~20자만 가능해요"
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
            Text(loadFailed ? "불러오지 못했어요" : "아직 하입한 트랙이 없어요")
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
            Text("하입 기록 전체 보기")
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
            NavigationLink { GenreSettingsView() } label: { settingsRow("장르 설정") }
            NavigationLink { LegalView(type: .terms) } label: { settingsRow("이용약관") }
            NavigationLink { LegalView(type: .privacy) } label: { settingsRow("개인정보처리방침") }
            Button { logout() } label: { settingsRow("로그아웃") }
            Button { showWithdrawAlert = true } label: { settingsRow("계정 삭제", destructive: true) }
        }
        .buttonStyle(.plain)
        .alert("계정을 삭제할까요?", isPresented: $showWithdrawAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { withdraw() }
        } message: {
            Text("하입·장르 등 모든 데이터가 삭제되며 되돌릴 수 없어요.")
        }
    }

    private func settingsRow(_ label: String, destructive: Bool = false) -> some View {
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
