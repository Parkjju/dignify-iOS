import SwiftUI

struct AppRootView: View {
    @State private var appSession = AppSession()

    var body: some View {
        Group {
            switch appSession.authState {
            case .unknown:
                LaunchLoadingView()
                    .task {
                        await appSession.resolveInitialState()
                    }
            case .signedOut:
                OnboardingFlowView()
            case .guest:
                MainTabView()
            case .onboardingRequired:
                NewUserOnboardingView()
            case .signedIn:
                MainTabView()
            }
        }
        .environment(appSession)
    }
}

/// 로고 로딩. 앱 실행 직후와 신규 유저가 곡 후보를 받는 동안(`NewUserOnboardingView`) 같이 쓴다.
/// 인디케이터는 둘러보기 후 로그인 대기에만 붙는다 — 앱 실행 로딩엔 없다.
struct LaunchLoadingView: View {
    var showsProgress = false

    var body: some View {
        ZStack {
            DSColor.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                DSBrandMark(size: 56)

                Text("Dignify")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColor.textPrimary)

                if showsProgress {
                    ProgressView()
                        .padding(.top, 12)
                }
            }
        }
    }
}

#Preview {
    AppRootView()
}
