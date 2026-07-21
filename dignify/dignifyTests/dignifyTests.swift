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

    @MainActor
    @Test func listenFiresOnceAfterThreshold() {
        let audio = FeedAudioController()
        var fired: [Int] = []
        audio.onListen = { fired.append($0) }

        // 훑고 지나간 스와이프는 청취가 아니다.
        audio.recordListenIfNeeded(trackId: 1, playedFor: 4.9)
        #expect(fired.isEmpty)

        audio.recordListenIfNeeded(trackId: 1, playedFor: 5)
        #expect(fired == [1])

        // 루프로 위치가 0으로 돌아가 임계값을 다시 넘어도 재발사하지 않는다.
        audio.recordListenIfNeeded(trackId: 1, playedFor: 0.1)
        audio.recordListenIfNeeded(trackId: 1, playedFor: 12)
        #expect(fired == [1])

        audio.recordListenIfNeeded(trackId: 2, playedFor: 7)
        #expect(fired == [1, 2])
    }

    @Test func whatsNewShowsOnlyOnUpdate() {
        let current = Changelog.releases.first!.version
        func show(_ lastSeen: String, returning: Bool = false) -> Bool {
            Changelog.shouldShowWhatsNew(lastSeen: lastSeen, current: current, isReturningUser: returning)
        }
        // 이전 버전에서 올라오면 뜬다.
        #expect(show("1.0.3") == true)
        // 같은 버전 재실행엔 안 뜬다.
        #expect(show(current) == false)
        // 첫 버전추적 실행(lastSeen 빈 값): 신규 온보딩 유저는 제외, 기존 유저만 표시.
        #expect(show("", returning: false) == false)
        #expect(show("", returning: true) == true)
        // 노트 없는 버전으로 올라가면 안 뜬다(returning이어도).
        #expect(Changelog.shouldShowWhatsNew(lastSeen: "1.0.3", current: "9.9.9", isReturningUser: true) == false)
    }

}
