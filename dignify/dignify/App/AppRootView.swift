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
            case .signedOut, .onboardingRequired:
                OnboardingFlowView()
            case .signedIn:
                MainTabView()
            }
        }
        .environment(appSession)
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            DSColor.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                DSBrandMark(size: 56)

                Text("Dignify")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
    }
}

#Preview {
    AppRootView()
}
