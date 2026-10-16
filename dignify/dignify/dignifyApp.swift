//
//  dignifyApp.swift
//  dignify
//
//  Created by 박경준 on 5/14/26.
//

import SwiftUI
import PostHog

@main
struct dignifyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 피드 아트워크 프리페치가 실효를 가지려면 기본값(디스크 ~10MB)보다 커야 한다.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)

        // PostHog: 앱 오픈/설치 등 라이프사이클은 켜두고(리텐션 원천), SwiftUI에서 무의미한
        // 화면 자동수집만 끈다. 나머지 이벤트는 수동으로 명시적으로 찍는다.
        // ponytail: 분석 키는 공개 전제라 시크릿 아님 — 하드코딩 OK.
        let POSTHOG_PROJECT_TOKEN = "phc_p4fbGm8GPStEkWCqTnCmFt5f6SgErTjrtaZBHQa9i57a"
        let POSTHOG_HOST = "https://us.i.posthog.com"

        let config = PostHogConfig(projectToken: POSTHOG_PROJECT_TOKEN, host: POSTHOG_HOST)
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }

    @Environment(\.scenePhase) private var scenePhase
    /// 미실행도 "앞에 없던 상태"로 친다. 제어 센터를 내렸다 올리는 건 inactive만 거쳐서 실행으로 안 센다.
    @State private var wasInBackground = true

    var body: some Scene {
        WindowGroup {
            AppRootView()
                // dignify://now-playing은 Live Activity의 widgetURL. 다른 URL은 아직 없다.
                .onOpenURL { url in
                    AppOpenTracker.opened(by: url.host == "now-playing" ? "app_opened_now_playing" : "app_opened_link")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                AppOpenTracker.cameToForeground()
            }
        }
    }
}
