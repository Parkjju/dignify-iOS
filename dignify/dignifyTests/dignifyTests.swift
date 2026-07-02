//
//  dignifyTests.swift
//  dignifyTests
//
//  Created by 박경준 on 5/14/26.
//

import Testing
@testable import dignify

struct dignifyTests {

    @Test func fadeVolumeRamps() async throws {
        let f = FeedAudioController.fadeVolume
        // fade in: 0→1 over first second
        #expect(f(0, 30, 1, 2) == 0)
        #expect(f(0.5, 30, 1, 2) == 0.5)
        // 중간 구간은 풀 볼륨
        #expect(f(15, 30, 1, 2) == 1)
        // fade out: 종료 2초 전부터 1→0
        #expect(f(29, 30, 1, 2) == 0.5)
        #expect(abs(f(30, 30, 1, 2)) < 0.0001)
    }

}
