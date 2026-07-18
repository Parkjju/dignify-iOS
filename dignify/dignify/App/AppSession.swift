import Foundation
import Observation
import PostHog
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppSession {
    /// AppDelegate가 APNs 토큰을 넘길 수 있게 살아있는 단일 인스턴스를 노출한다.
    /// 앱 수명 동안 AppRootView가 하나만 소유하므로 weak static으로 충분.
    static weak var current: AppSession?

    var authState: AuthState = .unknown

    /// 게스트가 계정 기능(하입·마이페이지 등)을 시도할 때 로그인 시트를 띄우는 트리거.
    /// 게이트 지점들이 true로 올리고, MainTabView가 시트로 관찰한다.
    var pendingSignIn = false

    /// 하입 상태 변경 브로드캐스트(trackId → 최신 하입 여부). 하입을 토글하는 화면이
    /// 기록하고, 같은 트랙을 들고 있는 다른 화면(피드↔마이페이지)이 관찰해 UI를 맞춘다.
    var hypeState: [Int: Bool] = [:]

    /// 장르 설정이 바뀔 때마다 증가. 피드가 관찰해 새 장르로 재fetch 한다.
    var genreVersion = 0

    /// 현재 선택된 탭. MainTabView가 소유·바인딩하고, 피드가 "지금 피드 탭인가"를
    /// 결정적으로 판단해 다른 탭에 있을 때 오디오를 켜지 않도록 쓴다.
    /// (onAppear/onDisappear는 TabView에서 신뢰할 수 없어 이 값으로 대체.)
    var selectedTab: AppTab = .feed

    let api: APIClient

    // ponytail: base URL 상수 하나. 환경 분기 필요해지면 그때 config로.
    private static let baseURL = URL(string: "https://dignify-backend-460750160818.us-central1.run.app")!

    init(api: APIClient = APIClient(baseURL: AppSession.baseURL)) {
        self.api = api
        AppSession.current = self
    }

    // MARK: - Push notifications

    /// 아티스트 요청 제출 직후 맥락에서 호출. 아직 안 물어봤으면 권한을 요청하고,
    /// 이미 허용됐으면 토큰만 갱신한다. 거부 상태면 조용히 무시(재알림 안 함).
    func requestPushAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
            default:
                break   // denied 등 → 무시
            }
        }
    }

    /// AppDelegate가 APNs 토큰을 받으면 호출. 로그인 유저의 토큰만 서버에 등록한다.
    /// environment는 빌드 종류로 결정 — 디버그=sandbox, 릴리스(TestFlight/출시)=production.
    func registerDeviceToken(_ hex: String) {
        guard authState == .signedIn else {
            print("[Push] 토큰 수신했지만 미로그인 상태 → 등록 스킵")
            return
        }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task {
            do {
                try await api.send(.deviceToken(token: hex, environment: environment))
                print("[Push] 디바이스 토큰 등록 성공 (\(environment))")
            } catch {
                print("[Push] 디바이스 토큰 등록 실패: \(error)")
            }
        }
    }

    /// 앱 시작 시 저장된 토큰으로 초기 진입 상태를 결정한다.
    /// 토큰 없음 → signedOut. 토큰 있음 → /users/me로 온보딩 완료 여부 확인.
    func resolveInitialState() async {
        // refresh까지 실패하면(토큰 만료·무효) 로그아웃 상태로 되돌린다.
        // 단 게스트는 잃을 세션이 없으므로 signedOut으로 끌어내리지 않는다
        // (게스트가 인증 엔드포인트를 건드려 401이 나도 게스트 브라우징을 유지).
        await api.setOnAuthFailure { [weak self] in
            Task { @MainActor in
                guard let self, self.authState != .guest else { return }
                self.authState = .signedOut
            }
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

    /// 로그인 없이 피드 등 계정 무관 기능만 둘러보는 게스트 모드로 진입한다.
    func enterGuest() {
        authState = .guest
    }

    /// Apple identity token으로 로그인/가입 후 온보딩 여부에 따라 진입 상태를 결정한다.
    /// 실패 시 throw — 호출부(로그인 화면)가 에러를 표시한다.
    func signInWithApple(identityToken: String) async throws {
        let tokens = try await api.send(.appleSignIn(identityToken: identityToken), as: AuthTokens.self)
        await api.setTokens(tokens)
        try await refreshAuthState()
        // 게스트→로그인 전환. distinct_id는 익명 그대로 이어져 전환 퍼널이 한 사람으로 연결된다.
        // ponytail: 백엔드가 안정적 userId를 안 내려줘 identify는 생략 — 익명 id로 리텐션·전환 다 나옴.
        PostHogSDK.shared.capture("signed_in", properties: ["is_new": authState == .onboardingRequired])
        pendingSignIn = false   // 게스트 게이트 시트에서 로그인한 경우 시트를 닫는다.
    }

    /// 장르 목록을 도메인 모델로 조회한다(온보딩·장르 설정 공용).
    func fetchGenres() async throws -> [Genre] {
        let res = try await api.send(.genres, as: API.GenresResponse.self)
        return res.genres.map { Genre(id: $0.genreId, name: $0.genreName) }
    }

    /// 유저 장르를 갱신하고 버전을 올려 피드 재fetch를 트리거한다.
    func updateGenres(ids: [Int]) async throws {
        try await api.send(.updateGenres(ids: ids))
        genreVersion += 1
    }

    /// 로그아웃 — 서버에 refresh token revoke 요청(best-effort) 후 로컬 토큰을 폐기한다.
    func logout() async {
        if let token = await api.currentRefreshToken {
            try? await api.send(.logout(refreshToken: token))   // 실패해도 로컬은 정리.
        }
        await api.setTokens(nil)
        authState = .signedOut
    }

    /// 회원 탈퇴 — 서버 계정 삭제 후 로컬 토큰 폐기. 실패 시 throw(호출부가 표시).
    func withdraw() async throws {
        guard let token = await api.currentRefreshToken else {
            authState = .signedOut
            return
        }
        try await api.send(.withdraw(refreshToken: token))
        await api.setTokens(nil)
        authState = .signedOut
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
    case guest
    case onboardingRequired
    case signedIn
}
