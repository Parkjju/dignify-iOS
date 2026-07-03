import SwiftUI
import AuthenticationServices

struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var appSession
    @State private var hasAppeared = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var legalDoc: LegalDocument?

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    DSBrandMark(size: 64)
                    Text("Dignify")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.96)
                        .foregroundStyle(DSColor.brand)
                    Text("Discover indie music and build your own taste.")
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
                    SignInWithAppleButton(.continue) { request in
                        // 백엔드가 신규 가입 시 email을 저장(NOT NULL)하므로 email 스코프 필수.
                        // 단 Apple은 email 클레임을 "최초 인증" 토큰에만 넣어줌.
                        request.requestedScopes = [.email]
                    } onCompletion: { handleAppleCompletion($0) }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
                    .disabled(isSigningIn)
                    .overlay {
                        if isSigningIn { ProgressView().tint(.white) }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.destructive)
                            .multilineTextAlignment(.center)
                    }
                    Text(termsText)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .tint(DSColor.brand)
                        .environment(\.openURL, OpenURLAction { url in
                            switch url.host {
                            case "terms":
                                legalDoc = .terms
                            case "privacy":
                                legalDoc = .privacy
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
            .sheet(item: $legalDoc) { SafariView(url: $0.url) }
        }
    }

    /// Apple 자격증명에서 identity token을 뽑아 서버 로그인으로 넘긴다.
    /// 성공 시 AppSession이 authState를 바꿔 AppRootView가 다음 화면으로 전환한다.
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            // 사용자가 시트를 취소한 경우는 에러로 표시하지 않는다.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = String(localized: "Sign-in failed. Please try again.")
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = String(localized: "Couldn't read your sign-in info. Please try again.")
                return
            }
            isSigningIn = true
            Task {
                defer { isSigningIn = false }
                do {
                    try await appSession.signInWithApple(identityToken: identityToken)
                } catch {
                    errorMessage = String(localized: "Sign-in failed. Please try again.")
                }
            }
        }
    }

    private var termsText: LocalizedStringKey {
        "By continuing, you agree to the [Terms of Service](dignify://terms) and [Privacy Policy](dignify://privacy)."
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppSession())
}
