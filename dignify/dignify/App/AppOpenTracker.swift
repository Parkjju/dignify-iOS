import Foundation
import PostHog

/// 앱이 어떤 경로로 앞에 나왔는지를 `app_opened_*` 이벤트 하나로 남긴다(안드로이드 `AppOpen`과 같은 이름).
///
/// - `app_opened_push` — 알림 탭(`type` 동봉)
/// - `app_opened_now_playing` — Live Activity 탭
/// - `app_opened_link` — 그 밖의 `dignify://` URL
/// - `app_opened_direct` — 위 신호가 없는 실행. iOS는 아이콘 탭과 앱 전환기 복귀를 구분해 주지 않는다.
///
/// 앞으로 나온 신호와 경로 신호(알림 탭·URL)는 도착 순서가 정해져 있지 않다 — 실측에서 건마다
/// 앞뒤가 바뀌었다. 그래서 앞으로 나온 뒤 잠깐 기다렸다가 그 앞뒤로 받은 경로로 판정한다.
/// 이미 앱을 보던 중에 누른 배너는 다음 실행보다 한참 앞이라 시각 조건에서 걸러진다.
/// SDK 자동 `Application Opened`는 그대로 두고, 이건 경로만 가르는 용도다.
@MainActor
enum AppOpenTracker {
    private static var via: (event: String, properties: [String: Any], at: Date)?
    private static var deciding = false

    /// 백그라운드(또는 미실행)에서 앞으로 나왔을 때 한 번 부른다.
    static func cameToForeground() {
        guard !deciding else { return }
        deciding = true
        let start = Date()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if let via, via.at > start.addingTimeInterval(-3) {
                PostHogSDK.shared.capture(via.event, properties: via.properties)
            } else {
                PostHogSDK.shared.capture("app_opened_direct")
            }
            via = nil
            deciding = false
        }
    }

    static func opened(by event: String, properties: [String: Any] = [:]) {
        via = (event, properties, Date())
    }
}
