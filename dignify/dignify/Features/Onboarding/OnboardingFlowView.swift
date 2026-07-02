import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var appSession
    @State private var path = NavigationPath()
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    DSBrandMark(size: 64)
                    Text("Dignify")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.96)
                        .foregroundStyle(DSColor.brand)
                    Text("인디 음악을 발굴하고 당신만의 취향을 쌓아가세요.")
                        .font(.system(size: 14))
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)
                .animation(.easeOut(duration: 0.5), value: hasAppeared)
                Spacer()
                VStack(spacing: 12) {
                    Button("Apple로 계속하기", systemImage: "apple.logo") {
                        path.append(OnboardingDestination.genreSelection)
                    }
                    .buttonStyle(DSAppleSignInButtonStyle())
                    Text(termsText)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .tint(DSColor.brand)
                        .environment(\.openURL, OpenURLAction { url in
                            switch url.host {
                            case "terms":
                                path.append(OnboardingDestination.legal(.terms))
                            case "privacy":
                                path.append(OnboardingDestination.legal(.privacy))
                            default:
                                break
                            }
                            return .handled
                        })
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.15), value: hasAppeared)
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 40)
            .background(DSColor.background)
            .onAppear { hasAppeared = true }
            .navigationDestination(for: OnboardingDestination.self) { destination in
                switch destination {
                case .genreSelection:
                    GenreSelectionView()
                case .legal(let type):
                    LegalView(type: type)
                }
            }
        }
    }

    private var termsText: LocalizedStringKey {
        "계속 진행하면 [이용약관](dignify://terms) 및 [개인정보처리방침](dignify://privacy)에 동의하는 것으로 간주됩니다."
    }

    private enum OnboardingDestination: Hashable {
        case genreSelection
        case legal(LegalView.DocumentType)
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppSession())
}
