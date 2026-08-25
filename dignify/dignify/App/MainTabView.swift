import SwiftUI

struct MainTabView: View {
    @Environment(AppSession.self) private var session
    /// 방금 온보딩을 마친 신규 유저 표시. 튜토리얼은 온보딩 플로우 앞단으로 옮겨갔고,
    /// 이 플래그는 "신규 가입자에게 What's New를 띄우지 않는다" 판정에만 남아 있다.
    /// NewUserOnboardingView가 세팅하고 아래 task가 소비 후 클리어한다.
    @AppStorage("didJustOnboard") private var didJustOnboard = false
    /// 업데이트 감지용. 신규 설치엔 안 띄우고 조용히 현재 버전만 기록.
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""
    /// 소리 2지선다를 한 번이라도 태웠는지(신규 가입·업데이트 유저 공통). 서버 플래그를 못 쓴다 —
    /// `is_onboarding_complete`를 내리면 구버전 앱이 옛 장르 온보딩을 다시 띄운다.
    @AppStorage("didSoundRounds") private var didSoundRounds = false
    @State private var showWhatsNew = false
    /// 라운드나 안내를 닫은 뒤에 이어서 띄울 What's New. 업데이트 유저는 두 화면 중
    /// 하나를 먼저 보므로, 여기 담아뒀다가 `onDismiss`에서 꺼낸다.
    @State private var pendingWhatsNew = false
    @State private var soundRounds: SoundRoundsPayload?
    @State private var showPersonalizationNotice = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        @Bindable var session = session
        TabView(selection: $session.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    content(for: tab)
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(DSColor.brand)
        .toolbarBackground(.hidden, for: .tabBar)
        .sheet(isPresented: $session.pendingSignIn) {
            OnboardingFlowView(mode: .gate)
        }
        // 같은 뷰에 .sheet 두 개(pendingSignIn)는 충돌 → 별도 노드에 부착.
        .background {
            Color.clear.sheet(isPresented: $showWhatsNew) {
                WhatsNewView(highlight: currentVersion)
            }
        }
        // 시트가 아니라 풀스크린이다 — 아래로 쓸어 닫을 수 있으면 라운드가 중간에 끊긴다.
        //
        // **`isPresented`가 아니라 `item`으로 연다.** 플래그로 열면 콘텐츠 클로저가 후보 배열이
        // 채워지기 전 값을 잡아서, 3라운드를 받아도 빈 배열을 든 화면이 뜬다(실제로 밟았다 —
        // 로그엔 200에 "3라운드 사용"이 찍히는데 화면은 마지막 장이었다).
        // item으로 열면 제시를 일으킨 그 값이 그대로 클로저에 들어온다.
        .background {
            Color.clear.fullScreenCover(item: $soundRounds, onDismiss: showPendingWhatsNew) { payload in
                SoundRoundsView(rounds: payload.rounds, isUpdate: true) { picked in
                    didSoundRounds = true
                    soundRounds = nil
                    // 방금 고른 곡이 시드다. 피드는 이미 불러온 뒤라 다시 받지 않으면
                    // 유저는 라운드를 마치고도 예전 순서를 본다.
                    if picked > 0 { session.feedReloadToken += 1 }
                }
            }
        }
        .background {
            Color.clear.fullScreenCover(isPresented: $showPersonalizationNotice,
                                        onDismiss: showPendingWhatsNew) {
                PersonalizationNoticeView {
                    didSoundRounds = true
                    showPersonalizationNotice = false
                }
            }
        }
        .task {
            // 기존 로그인 유저가 업데이트로 들어온 경우 = 온보딩 안 거침(didJustOnboard false) + signedIn.
            let isReturningUser = !didJustOnboard && session.authState == .signedIn
            let wantsWhatsNew = Changelog.shouldShowWhatsNew(lastSeen: lastSeenVersion,
                                                            current: currentVersion,
                                                            isReturningUser: isReturningUser)
            // 업데이트로 들어온 기존 유저는 한 번은 라운드(또는 안내)를 탄다. **닫히면 What's New를
            // 이어 붙인다** — 모달 두 개를 겹쳐 띄우면 하나가 조용히 안 뜨므로 `onDismiss`로 잇는다.
            // 1.1.0은 장르 설정이 사라진 게 핵심이라, 라운드만 보고 넘어가면 유저는 그 화면이 왜
            // 떴는지도 장르가 왜 없어졌는지도 모른 채 피드로 간다.
            if isReturningUser && !didSoundRounds {
                pendingWhatsNew = wantsWhatsNew
                if await startPersonalizationIntro() == false {
                    // 띄운 게 없으면(하입 3개 미만인데 후보가 아직 안 깔림) 이어 붙일 자리도 없다.
                    pendingWhatsNew = false
                    showWhatsNew = wantsWhatsNew
                }
            } else if wantsWhatsNew {
                showWhatsNew = true
            }
            lastSeenVersion = currentVersion
            didJustOnboard = false
        }
    }

    /// 라운드나 안내를 띄운다. **띄운 게 있으면 true** — 호출부가 What's New를 언제 낼지 가른다.
    ///
    /// **하입이 이미 쌓인 사람은 라운드를 태우지 않는다.** 시드는 최근 하입 3곡이라 라운드에서
    /// 고른 3곡이 시드를 통째로 차지하고, 그러면 쌓아온 취향이 밀려 피드가 잘못 구성된 것처럼 보인다.
    /// 기준을 3으로 둔 건 그 아래면 라운드가 채워 주는 쪽이 이득이라서다. 밀렸더라도
    /// 마이페이지의 추천 기준 곡에서 직접 고르면 되돌릴 수 있다(1.1.0에서 생긴 길이다).
    @discardableResult
    private func startPersonalizationIntro() async -> Bool {
        let stats = try? await session.api.send(.myStats(range: "all"), as: API.UserStats.self)
        // 통계를 못 받으면 라운드 쪽으로 간다 — 하입이 없는 유저에게 아무 설명 없이 넘어가는 것보다,
        // 하입이 있는 유저가 라운드를 한 번 더 보는 쪽이 덜 나쁘다.
        if let hypeCount = stats?.hypeCount, hypeCount >= 3 {
            showPersonalizationNotice = true
            return true
        }
        // 후보가 없으면(서버 미시딩) 커버를 아예 안 띄운다. 띄웠다 닫으면 화면이 번쩍이고,
        // 플래그를 태워버리면 시딩된 뒤에도 이 유저는 영영 라운드를 못 본다.
        let rounds = await SoundRoundsView.fetch(session)
        guard !rounds.isEmpty else { return false }
        soundRounds = SoundRoundsPayload(rounds: rounds)
        return true
    }

    /// 라운드·안내가 닫힌 뒤 What's New를 잇는다. 한 번만 띄운다.
    private func showPendingWhatsNew() {
        guard pendingWhatsNew else { return }
        pendingWhatsNew = false
        showWhatsNew = true
    }

    /// 게스트는 계정 기반 탭(마이페이지) 대신 로그인 유도 플레이스홀더를 본다.
    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        if tab == .myPage, session.authState == .guest {
            GuestSignInPromptView()
        } else {
            tab.makeContentView()
        }
    }
}

/// `fullScreenCover(item:)`에 실어 보내는 후보 묶음. 배열 자체는 Identifiable이 될 수 없어 감싼다.
private struct SoundRoundsPayload: Identifiable {
    let id = UUID()
    let rounds: [API.OnboardingCandidates.Round]
}

/// 게스트가 마이페이지 탭을 열었을 때 노출되는 로그인 유도 화면.
private struct GuestSignInPromptView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            DSBrandMark(size: 56)
            Text("Build your own taste")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text("Sign in to hype tracks, personalize your feed, and build your crate.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button {
                session.pendingSignIn = true
            } label: {
                Text("Sign in")
                    .font(DSTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
    }
}

#Preview {
    MainTabView()
        .environment(AppSession())
}
