import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    var authState: AuthState = .unknown

    let api: APIClient

    // ponytail: base URL 상수 하나. 환경 분기 필요해지면 그때 config로.
    private static let baseURL = URL(string: "https://dignify-backend-460750160818.us-central1.run.app")!

    init(api: APIClient = APIClient(baseURL: AppSession.baseURL)) {
        self.api = api
    }

    /// 앱 시작 시 저장된 토큰으로 초기 진입 상태를 결정한다.
    /// 토큰 없음 → signedOut. 토큰 있음 → /users/me로 온보딩 완료 여부 확인.
    func resolveInitialState() async {
        // refresh까지 실패하면(토큰 만료·무효) 로그아웃 상태로 되돌린다.
        await api.setOnAuthFailure { [weak self] in
            Task { @MainActor in self?.authState = .signedOut }
        }

        guard await api.isAuthenticated else {
            authState = .signedOut
            return
        }

        do {
            try await refreshAuthState()
        } catch {
            // onAuthFailure가 이미 처리했을 수 있으나 방어적으로 명시.
            authState = .signedOut
        }
    }

    /// Apple identity token으로 로그인/가입 후 온보딩 여부에 따라 진입 상태를 결정한다.
    /// 실패 시 throw — 호출부(로그인 화면)가 에러를 표시한다.
    func signInWithApple(identityToken: String) async throws {
        let tokens = try await api.send(.appleSignIn(identityToken: identityToken), as: AuthTokens.self)
        await api.setTokens(tokens)
        try await refreshAuthState()
    }

    /// 저장된 토큰 기준으로 /users/me를 조회해 signedIn / onboardingRequired를 분기한다.
    private func refreshAuthState() async throws {
        let profile = try await api.send(.myProfile, as: API.UserProfile.self)
        authState = profile.isOnboardingComplete ? .signedIn : .onboardingRequired
    }
}

enum AuthState {
    case unknown
    case signedOut
    case onboardingRequired
    case signedIn
}
