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

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
