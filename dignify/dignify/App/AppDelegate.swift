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
        return true
    }

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
        Task { @MainActor in
            var properties: [String: Any] = ["type": type]
            if let pushId { properties["push_id"] = pushId }
            AppOpenTracker.opened(by: "app_opened_push", properties: properties)
        }
        // 어드민 발송 이력의 열람 수. 위 이벤트와 달리 앱을 보던 중 누른 배너도 센다.
        if let pushId { Self.reportOpened(pushId) }
        switch type {
        case "curation":
            Task { @MainActor in
                AppSession.current?.pendingCurationOpen = true
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

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Push] APNs 디바이스 토큰 수신: \(hex.prefix(12))…")
        Task { @MainActor in AppSession.current?.registerDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // aps-environment 엔타이틀먼트 없거나 시뮬/네트워크 문제 시. 발송 못 할 뿐 앱엔 무해.
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
