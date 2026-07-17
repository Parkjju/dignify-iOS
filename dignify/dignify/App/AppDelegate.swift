import UIKit

/// SwiftUI에는 APNs 디바이스 토큰을 받는 API가 없어 UIApplicationDelegate가 필요하다.
/// 토큰을 hex 문자열로 바꿔 살아있는 AppSession(단일 인스턴스)에 넘긴다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in AppSession.current?.registerDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // aps-environment 엔타이틀먼트 없거나 시뮬/네트워크 문제 시. 발송 못 할 뿐 앱엔 무해.
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
