import SwiftUI

struct MainTabView: View {
    @Environment(AppSession.self) private var session
    /// 온보딩(장르 선택)을 막 마친 신규 유저에게만 튜토리얼을 띄우기 위한 일회성 플래그.
    /// GenreSelectionView가 세팅하고, 튜토리얼을 닫으면 클리어. 기존/업데이트 유저는 대상 아님.
    @AppStorage("pendingTutorial") private var pendingTutorial = false
    /// 업데이트 감지용. 신규 설치엔 안 띄우고 조용히 현재 버전만 기록.
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""
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
        .fullScreenCover(isPresented: showTutorial) {
            TutorialView { pendingTutorial = false }
        }
        // 같은 뷰에 .sheet 두 개(pendingSignIn)는 충돌 → 별도 노드에 부착.
        .background {
            Color.clear.sheet(isPresented: $showWhatsNew) {
                WhatsNewView(highlight: currentVersion)
            }
        }
        .task {
            // 기존 로그인 유저가 업데이트로 들어온 경우 = 온보딩 안 거침(pendingTutorial false) + signedIn.
            let isReturningUser = !pendingTutorial && session.authState == .signedIn
            if Changelog.shouldShowWhatsNew(lastSeen: lastSeenVersion, current: currentVersion, isReturningUser: isReturningUser) {
                showWhatsNew = true
            }
            lastSeenVersion = currentVersion
        }
    }

    private var showTutorial: Binding<Bool> {
        Binding(
            get: { pendingTutorial },
            set: { if !$0 { pendingTutorial = false } }
        )
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
            Text("Sign in to hype tracks, personalize your feed, and track your picks.")
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
