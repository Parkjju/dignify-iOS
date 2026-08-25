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

    /// 닉네임 아래 유형 배지용. 확정 유형은 전체 기간 기준으로만 본다 —
    /// 주간으로 보면 한 주 안 들었다고 정체성이 사라졌다 나타났다 한다.
    @State private var confirmedType: DiggingType?
    @State private var diggingModeFailed = false
    /// 마이페이지 코치마크를 이미 봤는지. 피드를 바꾸는 설정 둘이 그냥 목록의 한 줄로 보인다.
    @AppStorage("seenMyPageCoach") private var seenMyPageCoach = false
    /// 프로필을 받아 토글이 실제 값으로 그려진 뒤에 코치마크를 띄우기 위한 표시.
    @State private var profileLoaded = false

    #if DEBUG
    // 업데이트 유저 흐름을 다시 보기 위한 것들. 릴리즈 빌드엔 이 화면에서 아예 빠진다.
    @AppStorage("didJustOnboard") private var didJustOnboard = false
    @AppStorage("didSoundRounds") private var didSoundRounds = false
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""
    @AppStorage("seenFeedCoach") private var seenFeedCoach = false
    @AppStorage("seenPicksCoach") private var seenPicksCoach = false
    @AppStorage("seenSeedCoach") private var seenSeedCoach = false
    @State private var debugResetDone = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                diggingProfileEntry
                groupDivider
                settingsList
                Text(verbatim: "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.border)
                    .padding(.vertical, 24)
            }
        }
        .background(DSColor.background)
        .navigationTitle("My Page")
        .task { await loadProfile() }
        // 피드를 바꾸는 설정 둘을 한 번만 짚어 준다. 프로필을 받은 뒤에 띄우는 이유는
        // 그전엔 토글이 기본값(켜짐)으로 그려져 있어서, 실제 값과 다른 화면을 설명하게 되기 때문이다.
        .coachMarks(MyPageCoach.steps, screen: "mypage", isActive: !seenMyPageCoach && profileLoaded) {
            seenMyPageCoach = true
        }
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
        guard Nickname.isValid(new) else {
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
            } catch APIError.server("USER_NICKNAME_INVALID", _, _) {
                // 서버 메시지는 한국어로 고정돼 있어 그대로 못 쓴다 — 코드로만 분기하고 문구는 여기서 낸다.
                reopenNickEdit(previous: previous, attempted: new,
                               error: String(localized: "That nickname can't be used. Try another one."))
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

    /// 셀 부제목 자리에 실제 유형을 넣는다 — 확정 > 예상 > 아직 없음.
    /// 새 배지를 만드는 대신 이미 있는 한 줄을 쓴다. 유형이 곧 이 화면의 내용이라
    /// "Your taste, typed"보다 실제 유형이 언제나 더 알려주는 게 많다.
    @ViewBuilder
    private var entrySubtitle: some View {
        if let type = confirmedType {
            Text(verbatim: "\(type.emoji) \(type.name)")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.brand)
        } else {
            Text("Your taste, typed")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

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
                    entrySubtitle
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

    /// 설정 · 안내 · 약관 · 계정 네 묶음. 행이 열 개가 넘어가면서 무엇이 설정을 바꾸는 행이고
    /// 무엇이 읽기만 하는 행인지가 안 읽혔다. 묶음 사이에만 구분선을 둔다.
    private var settingsList: some View {
        VStack(spacing: 0) {
            // 1. 기능 — 실제로 무언가를 바꾸는 행들.
            // 이 화면에서 유일하게 피드 자체를 바꾸는 설정이라 묶음 맨 위에 둔다.
            diggingModeRow
                .coachAnchor(.followSwitch)
            // 껐을 때도 보여준다. 숨기면 기능이 사라진 것처럼 보이는데, 실제로는 다시 켜면
            // 그대로 쓰이는 설정이다. 꺼진 동안 무슨 뜻인지는 그 화면이 설명한다.
            NavigationLink { SeedPickerView() } label: { settingsRow("Recommend from") }
                .coachAnchor(.seedRow)
            NavigationLink { ArtistRequestHistoryView() } label: { settingsRow("Artist Requests") }
            // 차단은 로컬 저장이라 해제 경로가 여기밖에 없다. 되돌릴 수 없는 차단은 유저를 가둔다.
            NavigationLink { BlockedUsersView() } label: { settingsRow("Blocked Users") }

            groupDivider

            // 2. 안내 — 읽기만 하는 행들. 인스타도 "우리를 더 보는" 자리라 여기 묶인다.
            Button { showTutorial = true } label: { settingsRow("How to Use") }
            Button { showWhatsNew = true } label: { settingsRow("What's New") }
            // Link는 유니버설 링크라 인스타 앱이 있으면 앱으로, 없으면 사파리로 알아서 간다.
            Link(destination: instagramURL) { settingsRow("dignify on Instagram") }

            groupDivider

            // 3. 약관
            Button { legalDoc = .terms } label: { settingsRow("Terms of Service") }
            Button { legalDoc = .privacy } label: { settingsRow("Privacy Policy") }

            groupDivider

            // 4. 계정 — 되돌리기 어려운 것들만 마지막에 모은다.
            Button { logout() } label: { settingsRow("Log Out") }
            Button { showWithdrawAlert = true } label: { settingsRow("Delete Account", destructive: true) }

            #if DEBUG
            groupDivider
            debugResetRow
            #endif
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
            // 픽을 빠뜨리면 안 된다 — FK가 ON DELETE CASCADE라 내가 만든 픽과 거기 붙은 반응까지
            // 실제로 사라진다. 남의 지면에 올린 게 없어지는 건 하입이 없어지는 것과 무게가 다르다.
            Text("All your data, including your picks, hypes, and genres, will be deleted permanently.")
        }
    }

    /// 한국어 기기는 국내 계정, 그 외는 글로벌 계정. 약관 링크와 같은 로케일 분기.
    private var instagramURL: URL {
        let ko = Locale.current.language.languageCode?.identifier == "ko"
        return URL(string: ko ? "https://instagram.com/dignify_music.kr"
                              : "https://instagram.com/dignify_music")!
    }

    private var groupDivider: some View {
        Divider().padding(.horizontal, 20).padding(.vertical, 8)
    }

    #if DEBUG
    /// **디버그 빌드에만 있다.** 로그인 상태는 그대로 두고 "방금 업데이트한 기존 유저"의
    /// 플래그만 되돌린다. 앱을 지우면 신규 설치가 되어 온보딩을 타므로 그 경로로는
    /// 업데이트 유저 흐름(라운드 → What's New → 코치마크)을 볼 수가 없다.
    ///
    /// `MainTabView`의 판정은 실행 직후 `.task`에서 한 번만 돌기 때문에 **앱을 껐다 켜야** 보인다.
    private var debugResetRow: some View {
        Button {
            didJustOnboard = false          // 신규 가입이 아니라 기존 유저로 본다
            didSoundRounds = false          // 소리 2지선다를 다시 태운다
            lastSeenVersion = "1.0.10"      // 지금 버전과 달라야 What's New가 뜬다
            seenFeedCoach = false
            seenMyPageCoach = false
            seenSeedCoach = false
            seenPicksCoach = false
            debugResetDone = true
        } label: {
            settingsRow("업데이트 유저 상태로 초기화 (DEBUG)")
        }
        .alert("초기화했어요", isPresented: $debugResetDone) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(verbatim: "앱을 완전히 껐다 켜면 라운드 → What's New → 코치마크 순서로 뜹니다.")
        }
    }
    #endif

    /// 토글 하나로는 무엇이 켜지는지 알 수 없어서 한 줄 설명을 붙인다.
    /// 낙관적으로 먼저 바꾸고 실패하면 되돌린다 — 스위치가 손가락을 따라오지 않으면 고장으로 읽힌다.
    private var diggingModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { appSession.diggingMode }, set: { setDiggingMode($0) })) {
                Text("Follow my hypes")
                    .font(.system(size: 15))
                    .foregroundStyle(DSColor.textPrimary)
            }
            .tint(DSColor.brand)
            Text("On, the feed plays tracks that sound like the ones you hyped. Off, it plays anything.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
            if diggingModeFailed {
                Text("Couldn't save. Please try again.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func setDiggingMode(_ enabled: Bool) {
        diggingModeFailed = false
        // 되돌리기와 피드 재요청은 AppSession이 한다 — 피드 안 버튼과 같은 경로여야
        // 어느 쪽으로 껐든 결과가 같다.
        Task { diggingModeFailed = !(await appSession.setDiggingMode(enabled, source: "mypage")) }
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
        // 배지는 실패해도 예상 유형으로 폴백되므로 둘을 나란히 쏘고 각각 try?로 삼킨다.
        async let profileResult = try? appSession.api.send(.myProfile, as: API.UserProfile.self)
        async let statsResult = try? appSession.api.send(.myStats(range: "all"), as: API.UserStats.self)

        if let profile = await profileResult {
            nickname = profile.nickname
            appSession.diggingMode = profile.diggingMode ?? true
        }
        confirmedType = (await statsResult).map(DiggingStats.init)?.type
        profileLoaded = true
    }
}

/// 닉네임 규칙. 백엔드 `NicknameUpdateRequest @Pattern`과 **글자 하나까지 같아야** 한다 —
/// 어긋나면 클라가 통과시킨 값이 서버에서 400으로 튕기거나, 멀쩡한 값이 못 올라간다.
enum Nickname {
    static let pattern = "^[a-zA-Z0-9_가-힣]{1,20}$"

    static func isValid(_ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview {
    NavigationStack {
        MyPageView()
            .environment(AppSession())
    }
}
