import SwiftUI
import AuthenticationServices

struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var appSession
    @State private var path = NavigationPath()
    @State private var hasAppeared = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?

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
                case .legal(let type):
                    LegalView(type: type)
                }
            }
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
            errorMessage = "로그인에 실패했어요. 다시 시도해 주세요."
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "로그인 정보를 읽지 못했어요. 다시 시도해 주세요."
                return
            }
            isSigningIn = true
            Task {
                defer { isSigningIn = false }
                do {
                    try await appSession.signInWithApple(identityToken: identityToken)
                } catch {
                    errorMessage = "로그인에 실패했어요. 다시 시도해 주세요."
                }
            }
        }
    }

    private var termsText: LocalizedStringKey {
        "계속 진행하면 [이용약관](dignify://terms) 및 [개인정보처리방침](dignify://privacy)에 동의하는 것으로 간주됩니다."
    }

    private enum OnboardingDestination: Hashable {
        case legal(LegalView.DocumentType)
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppSession())
}
