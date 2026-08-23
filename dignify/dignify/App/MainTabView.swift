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
    @State private var soundRounds: [API.OnboardingCandidates.Round] = []
    @State private var showSoundRounds = false

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
        .background {
            Color.clear.fullScreenCover(isPresented: $showSoundRounds) {
                SoundRoundsView(rounds: soundRounds) { picked in
                    didSoundRounds = true
                    showSoundRounds = false
                    // 방금 고른 곡이 시드다. 피드는 이미 불러온 뒤라 다시 받지 않으면
                    // 유저는 라운드를 마치고도 예전 순서를 본다.
                    if picked > 0 { session.feedReloadToken += 1 }
                }
            }
        }
        .task {
            // 기존 로그인 유저가 업데이트로 들어온 경우 = 온보딩 안 거침(didJustOnboard false) + signedIn.
            let isReturningUser = !didJustOnboard && session.authState == .signedIn
            // 업데이트로 들어온 기존 유저도 한 번은 라운드를 탄다. What's New와 같이 띄우지 않는다 —
            // 이번 릴리즈에선 이 화면 자체가 새 소식이고, 모달 두 개가 겹치면 하나가 조용히 안 뜬다.
            if isReturningUser && !didSoundRounds {
                // 후보가 없으면(서버 미시딩) 커버를 아예 안 띄운다. 띄웠다 닫으면 화면이 번쩍이고,
                // 플래그를 태워버리면 시딩된 뒤에도 이 유저는 영영 라운드를 못 본다.
                soundRounds = await SoundRoundsView.fetch(session)
                showSoundRounds = !soundRounds.isEmpty
            } else if Changelog.shouldShowWhatsNew(lastSeen: lastSeenVersion, current: currentVersion, isReturningUser: isReturningUser) {
                showWhatsNew = true
            }
            lastSeenVersion = currentVersion
            didJustOnboard = false
        }
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
