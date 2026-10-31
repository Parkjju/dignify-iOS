import SwiftUI

struct MainTabView: View {
    @Environment(AppSession.self) private var session
    /// 방금 온보딩을 마친 신규 유저 표시. "신규 가입자에게 What's New를 띄우지 않는다" 판정에만 쓴다.
    /// NewUserOnboardingView가 세팅하고 아래 task가 소비 후 클리어한다.
    @AppStorage("didJustOnboard") private var didJustOnboard = false
    /// 업데이트 감지용. 신규 설치엔 안 띄우고 조용히 현재 버전만 기록.
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""
    @AppStorage("seenFeedCoach") private var seenFeedCoach = false
    @State private var showWhatsNew = false

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
        // 광고성 동의·거부 결과 통지(제50조 7항). 피드 팝업·설정 화면 어디서 바꿔도 여기 한 곳에서 뜬다.
        .overlay {
            if let notice = session.consentNotice {
                DSNoticePopup(title: "Notification settings saved", message: LocalizedStringKey(notice)) {
                    withAnimation { session.consentNotice = nil }
                }
            }
        }
        .task {
            // 기존 로그인 유저가 업데이트로 들어온 경우 = 온보딩 안 거침(didJustOnboard false) + signedIn.
            let isReturningUser = !didJustOnboard && session.authState == .signedIn
            let wantsWhatsNew = Changelog.shouldShowWhatsNew(lastSeen: lastSeenVersion,
                                                            current: currentVersion,
                                                            isReturningUser: isReturningUser)
            // 기존 계정(업데이트·재설치 후 로그인)은 앱을 이미 써 본 사람이다 — 코치마크를 건너뛰고,
            // 그래서 피드가 뜨자마자 첫 실행 동의 팝업만 받는다(`FeedView.offerAdConsentIfNeeded`).
            // 시드 고르기는 신규 가입 온보딩에서만 탄다(1.1.0 업데이트 유저용 안내는 1.3.2에서 뺐다).
            if isReturningUser { seenFeedCoach = true }
            if wantsWhatsNew { showWhatsNew = true }
            lastSeenVersion = currentVersion
            didJustOnboard = false
        }
    }

    /// 게스트는 피드만 쓴다. Picks·마이 탭은 로그인 유도 화면으로 막는다(feed_coachmark 1.0).
    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        if tab != .feed, session.authState == .guest {
            GuestSignInPromptView()
        } else {
            tab.makeContentView()
        }
    }
}

/// 게스트가 Picks·마이 탭을 열었을 때 노출되는 로그인 유도 화면.
private struct GuestSignInPromptView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            DSBrandMark(size: 56)
            Text("Build your own taste")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text("Sign in to save the tracks you love and build a feed that fits your taste.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button {
                session.pendingSignIn = true
            } label: {
                Text("Find my taste")
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
