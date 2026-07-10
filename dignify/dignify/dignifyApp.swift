//
//  dignifyApp.swift
//  dignify
//
//  Created by 박경준 on 5/14/26.
//

import SwiftUI

@main
struct dignifyApp: App {
    init() {
        // 피드 아트워크 프리페치가 실효를 가지려면 기본값(디스크 ~10MB)보다 커야 한다.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
