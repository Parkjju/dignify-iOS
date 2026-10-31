import UIKit
import UserNotifications
import PostHog

/// SwiftUI에는 APNs 디바이스 토큰을 받는 API가 없어 UIApplicationDelegate가 필요하다.
/// 토큰을 hex 문자열로 바꿔 살아있는 AppSession(단일 인스턴스)에 넘긴다.
/// UNUserNotificationCenterDelegate로 포그라운드에서도 배너를 띄운다.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 좋아요 알림 팝업은 두 번째 실행부터다(첫 실행엔 동의 팝업이 따로 뜬다).
        // ponytail: 백그라운드 실행(알림 액션 등)도 한 번으로 센다. "두 번째 이상"만 보므로 상관없다.
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.launchCountKey) + 1, forKey: Self.launchCountKey)
        // 광고성 알림(서버 `category = AD_PUSH`)에 「수신거부」 버튼. 경로를 글로만 안내하거나 로그인을
        // 요구하면 위반이라(KISA 안내서 44쪽) 알림에서 바로 처리한다. 앱을 열지 않는다(옵션 없음 = 백그라운드).
        let optOut = UNNotificationAction(identifier: Self.optOutAction, title: String(localized: "Unsubscribe"),
                                          options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "AD_PUSH", actions: [optOut], intentIdentifiers: []),
        ])
        return true
    }

    static let launchCountKey = "launchCount"
    private static let optOutAction = "OPT_OUT"
    /// 수신거부는 로그인 없이 기기 토큰으로 처리한다. 콜드 스타트엔 APNs 토큰이 아직 안 와 있을 수 있어 둔다.
    private static let deviceTokenKey = "apnsDeviceToken"

    /// 앱이 포그라운드일 때 도착한 푸시도 배너·소리로 보여준다(기본은 안 뜸).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// 푸시를 탭했을 때 종류별로 갈라 보낸다. 알림이 약속한 것을 못 보여주면 알림을 띄운 뜻이 없다 —
    /// 곡을 보여주겠다고 해놓고 일반 피드 첫 화면을 열거나, 반응이 달렸다고 해놓고 남의 픽 목록을 열면
    /// 유저는 자기가 뭘 눌렀는지 모른 채 앱만 켜게 된다.
    ///
    /// `notice`(TYPE 없이 보낸 공지)는 분기가 없는 게 맞다 — 갈 데를 지정하지 않은 알림이다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "unknown"
        // 서버 배포(2026-10-19) 전 알림엔 없다 — 그땐 키째 뺀다
        let pushId = userInfo["push_id"] as? String
        // 「수신거부」는 앱을 연 게 아니다 — 열람으로도 안 세고 피드도 안 건드린다.
        if response.actionIdentifier == Self.optOutAction {
            Task {
                await Self.optOut(pushId: pushId)
                completionHandler()
            }
            return
        }
        Task { @MainActor in
            var properties: [String: Any] = ["type": type]
            if let pushId { properties["push_id"] = pushId }
            AppOpenTracker.opened(by: "app_opened_push", properties: properties)
        }
        // 어드민 발송 이력의 열람 수. 위 이벤트와 달리 앱을 보던 중 누른 배너도 센다.
        if let pushId { Self.reportOpened(pushId) }
        switch type {
        case "curation", "new_release", "weekly_pick":
            // 피드 앞 구간을 이 알림의 곡으로 갈아 끼운다. APNs 숫자 배열은 NSNumber로 온다.
            let trackIds = (userInfo["trackIds"] as? [NSNumber])?.map(\.intValue) ?? []
            Task { @MainActor in
                AppSession.current?.pendingPushOpen = PushOpen(type: type, trackIds: trackIds)
                AppSession.current?.selectedTab = .feed
            }
        case "pick_reaction":
            // 어느 픽인지가 페이로드에 없어서 **내 픽 목록**까지만 간다. 픽 탭으로 보내면
            // 내 픽이 목록 어디에 있는지 알 수 없어 반응이 달린 픽을 못 찾는다.
            Task { @MainActor in
                AppSession.current?.pendingMyPicksOpen = true
                AppSession.current?.selectedTab = .myPage
            }
        default:
            break
        }
        completionHandler()
    }

    /// 알림을 눌렀다고 서버에 알린다. AppSession을 거치지 않는 건 콜드 스타트에 아직 없을 수 있어서고,
    /// 토큰을 안 붙이는 건 만료 토큰이면 permitAll 경로에서도 서버가 401을 내서다. 실패는 버린다.
    private static func reportOpened(_ pushId: String) {
        var request = URLRequest(url: AppSession.baseURL.appending(path: "push/\(pushId)/opened"))
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }

    /// 알림의 「수신거부」. 인증 없이 기기 토큰으로 서버 동의를 거두고, 결과를 로컬 알림으로 통지한다(제50조 7항) —
    /// 앱이 안 떠 있을 수 있어 앱 안 팝업으로는 못 보여 준다. 실패해도 알린다(거부가 안 됐는데 된 줄 알면 안 된다).
    private static func optOut(pushId: String?) async {
        var body = String(localized: "Couldn't unsubscribe. Turn off ad notifications in My Page › Notifications.")
        if let pushId, let token = UserDefaults.standard.string(forKey: deviceTokenKey) {
            var request = URLRequest(url: AppSession.baseURL.appending(path: "push/\(pushId)/opt-out"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(["deviceToken": token])
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let res = try? JSONDecoder().decode(API.AdPushConsent.self, from: data) {
                UserDefaults.standard.set(res.adPush, forKey: AppSession.adPushConsentKey)
                body = AppSession.consentNoticeText(adPush: res.adPush, processedAt: res.processedAt)
            }
        }
        let content = UNMutableNotificationContent()
        content.body = body
        content.userInfo = ["type": "consent_notice"]
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "consent_notice", content: content, trigger: nil))
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Self.deviceTokenKey)
        print("[Push] APNs 디바이스 토큰 수신: \(hex.prefix(12))…")
        Task { @MainActor in AppSession.current?.registerDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // aps-environment 엔타이틀먼트 없거나 시뮬/네트워크 문제 시. 발송 못 할 뿐 앱엔 무해.
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
