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

    /// 푸시를 탭했을 때. 큐레이션 푸시면 피드 탭으로 보내고 세트를 다시 앞세우게 한다 —
    /// 곡을 보여주겠다고 알림을 띄워놓고 일반 피드 첫 화면을 열면 그 곡을 못 찾는다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let type = response.notification.request.content.userInfo["type"] as? String ?? "unknown"
        PostHogSDK.shared.capture("push_opened", properties: ["type": type])
        if type == "curation" {
            Task { @MainActor in
                AppSession.current?.pendingCurationOpen = true
                AppSession.current?.selectedTab = .feed
            }
        }
        completionHandler()
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
