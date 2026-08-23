//
//  dignifyTests.swift
//  dignifyTests
//
//  Created by 박경준 on 5/14/26.
//

import Foundation   // Locale — import는 전이되지 않아서 @testable import만으론 안 온다.
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

    @MainActor
    @Test func playbackStartFiresOnceWhenAudioActuallyMoves() {
        let audio = FeedAudioController()
        var fired: [Int] = []
        audio.onPlaybackStart = { trackId, _ in fired.append(trackId) }

        // 시작을 열지 않았으면 위치가 흘러도 발사하지 않는다(마이페이지 미리듣기 등).
        audio.reportPlaybackStartIfNeeded(trackId: 1, position: 0.5)
        #expect(fired.isEmpty)

        // play()를 불렀어도 위치가 0이면 아직 무음 — 버퍼링 중이다.
        audio.markPlayRequested()
        audio.reportPlaybackStartIfNeeded(trackId: 1, position: 0)
        #expect(fired.isEmpty)

        audio.reportPlaybackStartIfNeeded(trackId: 1, position: 0.05)
        #expect(fired == [1])

        // 같은 트랙이 계속 흘러도, 루프로 0에 돌아왔다 다시 흘러도 재발사하지 않는다.
        audio.reportPlaybackStartIfNeeded(trackId: 1, position: 1.2)
        audio.reportPlaybackStartIfNeeded(trackId: 1, position: 0.1)
        #expect(fired == [1])

        // 다음 트랙은 setCurrent가 다시 열어줘야 발사된다.
        audio.reportPlaybackStartIfNeeded(trackId: 2, position: 0.4)
        #expect(fired == [1])
        audio.markPlayRequested()
        audio.reportPlaybackStartIfNeeded(trackId: 2, position: 0.4)
        #expect(fired == [1, 2])
    }

    @MainActor
    @Test func dwellAccumulatesAcrossLoops() {
        let audio = FeedAudioController()
        var fired: [(Int, Double)] = []
        audio.onDwell = { fired.append(($0, $1)) }

        // currentTrackId가 없으면(피드 밖) 발사하지 않는다.
        audio.advanceDwell(to: 3)
        audio.flushDwell()
        #expect(fired.isEmpty)

        audio.togglePreview(trackId: 7, url: URL(string: "https://example.com/a.m4a")!)
        audio.advanceDwell(to: 4)
        audio.advanceDwell(to: 29)
        audio.advanceDwell(to: 0.2)     // 루프 — 직전 위치가 누적으로 넘어간다.
        audio.advanceDwell(to: 6)
        audio.flushDwell()
        #expect(fired.count == 1)
        #expect(abs(fired[0].1 - 35) < 0.0001)
        #expect(fired[0].0 == 7)

        // flush 후엔 카운터가 비어 재발사되지 않는다.
        audio.flushDwell()
        #expect(fired.count == 1)
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

    /// 픽 폴백 제목은 서버에 저장하지 않고 매번 클라가 조립하므로, 분기가 어긋나면
    /// 목록 전체의 제목이 한 번에 틀어진다. 3분기를 못박아 둔다.
    ///
    /// 기대값을 영어로 박아두면 시뮬레이터 언어가 한국어일 때 깨진다 —
    /// `String(localized:locale:)`의 `locale`은 언어 테이블을 고르지 않는다(번들이 고른다).
    /// 그래서 실행 중인 언어의 포맷 문자열을 번들에서 꺼내 기대값을 만든다.
    @Test func pickFallbackTitleBranches() {
        func title(tracks: Int, artists: Int) -> String {
            PickTitle.fallback(firstTrack: "Ivy", firstArtist: "Frank Ocean",
                               trackCount: tracks, distinctArtistCount: artists)
        }
        // 키가 테이블에 없으면 키 자체가 돌아오고, 그게 곧 en 원문이다.
        func expected(_ key: String, _ args: CVarArg...) -> String {
            String(format: Bundle.main.localizedString(forKey: key, value: nil, table: nil),
                   arguments: args)
        }
        #expect(title(tracks: 1, artists: 1) == expected("%@ by %@", "Ivy", "Frank Ocean"))
        #expect(title(tracks: 7, artists: 1)
                == expected("%@ by %@ and %lld more", "Ivy", "Frank Ocean", 6))
        // 아티스트가 여럿이면 곡 수가 아니라 아티스트 수로 센다.
        #expect(title(tracks: 7, artists: 4) == expected("%@ and %lld others", "Frank Ocean", 3))

        // 공백만 남은 제목은 nil로 보낸다 — 빈 문자열과 null이 둘 다 "제목 없음"이면 판정이 갈린다.
        #expect(PickTitle.normalized("   ") == nil)
        #expect(PickTitle.normalized("   여름밤 ") == "여름밤")
    }

    /// ko 어순이 en과 반대라 xcstrings에 위치 인자(`%2$@`)가 들어가 있다. 순서가 어긋나면
    /// "Ivy의 Frank Ocean" 같은 문장이 나오는데, 크래시가 없어 눈으로만 잡힌다.
    ///
    /// `String(localized:locale:)`으로는 검증할 수 없다 — `locale`은 숫자·날짜 표시 형식만
    /// 바꾸고, 어느 언어 테이블을 읽을지는 번들이 정한다(테스트 프로세스는 en으로 뜬다).
    /// 그래서 ko.lproj를 직접 열어 컴파일된 문자열을 꺼내 포맷한다.
    @Test func koreanTitleArgumentsStayInOrder() throws {
        let ko = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj").flatMap(Bundle.init(path:)),
                              "앱 번들에 ko.lproj가 없다 — 한국어가 빌드에 안 실렸다")
        // 키가 없으면 키 자체가 돌아오므로 아래 비교에서 그대로 드러난다.
        func format(_ key: String, _ args: CVarArg...) -> String {
            String(format: ko.localizedString(forKey: key, value: nil, table: nil), arguments: args)
        }
        #expect(format("%@ by %@", "Ivy", "Frank Ocean") == "Frank Ocean의 Ivy")
        #expect(format("%@ by %@ and %lld more", "Ivy", "Frank Ocean", 6) == "Frank Ocean의 Ivy 외 6곡")
        #expect(format("%@ and %lld others", "Frank Ocean", 3) == "Frank Ocean 외 3명")
    }

    /// 두 축이 어떻게 나오든 유형이 하나로 정해진다. 유형은 이제 행동으로만 확정된다
    /// — 온보딩 퀴즈(예상 유형)는 소리 2지선다로 대체되면서 사라졌다.
    @Test func diggingTypeMapping() {
        #expect(DiggingType(selective: true, concentrated: true) == .purist)
        #expect(DiggingType(selective: true, concentrated: false) == .restlessCurator)
        #expect(DiggingType(selective: false, concentrated: true) == .loyalist)
        #expect(DiggingType(selective: false, concentrated: false) == .omnivore)
    }

    /// 하입 직후 재구성 — 이미 지나간 곡이 새 페이지 상위로 올라와도 다시 안 보여야 한다.
    /// 정렬 기준(시드)이 바뀌는 게 이 기능의 전부라, 서버가 같은 곡을 다시 주는 건 정상이고
    /// 걸러내는 건 클라 몫이다.
    @Test func upcomingDropsAlreadySeenTracks() {
        func feed(_ id: Int) -> Feed {
            Feed(trackId: id, trackName: "t\(id)", artistName: "a", artworkUrl: "",
                 previewUrl: "", trackViewUrl: "", isHyped: false,
                 genreName: nil, genreNameEn: nil)
        }
        let kept = [feed(1), feed(2), feed(3)]

        // 겹치는 1·3은 빠지고 순서는 서버가 준 그대로 유지된다.
        let tail = FeedView.upcoming(after: kept, from: [feed(3), feed(9), feed(1), feed(7)])
        #expect(tail.map(\.trackId) == [9, 7])

        // 전부 겹치면 빈 배열 — 호출부가 이걸 보고 기존 꼬리를 그대로 둔다.
        #expect(FeedView.upcoming(after: kept, from: [feed(2), feed(1)]).isEmpty)

        // 첫 진입처럼 지나간 곡이 없으면 받은 그대로.
        #expect(FeedView.upcoming(after: [], from: [feed(5), feed(6)]).map(\.trackId) == [5, 6])
    }

}
