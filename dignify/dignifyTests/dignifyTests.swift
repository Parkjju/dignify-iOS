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

    /// 카피 키는 `genres.genre_name_en` 원문과 글자 하나까지 같아야 하고, 어긋나면
    /// 크래시 없이 설명만 조용히 사라진다. 그래서 실제 장르명으로 매칭을 못박아 둔다.
    /// 목록은 2026-07-27 프로덕션 기준 활성 트랙이 있는 장르 전부.
    /// `/genres`가 트랙 1개라도 있는 장르를 모두 내려주므로 꼬리 3개도 화면에 뜬다 —
    /// 설명 없이 노출되지 않게 여기서 같이 막는다.
    @Test func genreGuideCoversLiveGenres() {
        let live = ["Hip-Hop/Rap", "Rock", "Pop", "Jazz", "Dance", "Country",
                    "R&B/Soul", "Electronic", "K-Pop", "Latin", "CCM",
                    "Alternative", "Bass", "Dubstep"]
        for name in live {
            #expect(GenreGuide.blurb(for: name) != nil, "no blurb for \(name)")
        }
        // 퀴즈가 추천하는 장르는 전부 설명이 있어야 한다(결과 화면이 이름만 덩그러니 뜨지 않게).
        for name in TasteQuiz.catalogOrder {
            #expect(GenreGuide.blurb(for: name) != nil, "no blurb for recommended genre \(name)")
        }
        // 모르는 장르는 크래시 없이 nil — 서버가 장르를 늘려도 화면은 멀쩡해야 한다.
        #expect(GenreGuide.blurb(for: "Shoegaze") == nil)
        #expect(GenreGuide.blurb(for: nil) == nil)
        // 현지화된 이름(ko)으로는 매칭되지 않는다 — nameEn을 써야 하는 이유.
        #expect(GenreGuide.blurb(for: "힙합") == nil)
    }

    /// 퀴즈 점수표는 손으로 짠 상수라 한 줄만 고쳐도 균형이 무너진다.
    /// 장르 문항의 모든 답 조합을 돌려 (1) 도달 못 하는 죽은 장르 (2) 과반을 먹는 장르를 잡는다.
    /// 배점을 조정할 땐 이 테스트를 먼저 돌려 볼 것.
    @Test func tasteQuizMappingIsBalanced() {
        // 장르 점수가 걸린 문항만 조합한다(유형 문항은 장르에 기여하지 않음).
        let genreQuestions = TasteQuiz.questions.indices.filter { i in
            TasteQuiz.questions[i].options.contains { !$0.genres.isEmpty }
        }
        var combos: [[Int]] = [[]]
        for q in genreQuestions {
            combos = combos.flatMap { combo in
                TasteQuiz.questions[q].options.indices.map { combo + [$0] }
            }
        }
        #expect(combos.count > 100, "조합이 너무 적으면 이 테스트는 의미가 없다")

        var top3Hits: [String: Int] = [:]
        for combo in combos {
            // 답 배열은 문항 인덱스와 정렬돼야 하므로 장르 문항 위치에만 채워 넣는다.
            var answers = [Int](repeating: 0, count: TasteQuiz.questions.count)
            for (slot, q) in genreQuestions.enumerated() { answers[q] = combo[slot] }
            for name in TasteQuiz.result(answers: answers).genreNames {
                top3Hits[name, default: 0] += 1
            }
        }

        for genre in TasteQuiz.catalogOrder {
            let share = Double(top3Hits[genre] ?? 0) / Double(combos.count)
            #expect(share > 0, "\(genre): 어떤 답 조합으로도 추천되지 않는다")
            #expect(share < 0.55, "\(genre): 결과의 \(Int(share * 100))%를 먹는다 — 문항이 무의미해짐")
        }
    }

    /// 픽 폴백 제목은 서버에 저장하지 않고 매번 클라가 조립하므로, 분기가 어긋나면
    /// 목록 전체의 제목이 한 번에 틀어진다. 3분기 × ko/en을 못박아 둔다.
    /// (ko 어순이 반대라 xcstrings에 위치 인자 `%2$@`가 들어가 있다 — 그게 깨져도 여기서 잡힌다.)
    @Test func pickFallbackTitleBranches() {
        func title(tracks: Int, artists: Int, _ language: String) -> String {
            PickTitle.fallback(firstTrack: "Ivy", firstArtist: "Frank Ocean",
                               trackCount: tracks, distinctArtistCount: artists,
                               locale: Locale(identifier: language))
        }
        #expect(title(tracks: 1, artists: 1, "en") == "Ivy by Frank Ocean")
        #expect(title(tracks: 7, artists: 1, "en") == "Ivy by Frank Ocean and 6 more")
        // 아티스트가 여럿이면 곡 수가 아니라 아티스트 수로 센다.
        #expect(title(tracks: 7, artists: 4, "en") == "Frank Ocean and 3 others")
        #expect(title(tracks: 1, artists: 1, "ko") == "Frank Ocean의 Ivy")
        #expect(title(tracks: 7, artists: 1, "ko") == "Frank Ocean의 Ivy 외 6곡")
        #expect(title(tracks: 7, artists: 4, "ko") == "Frank Ocean 외 3명")

        // 공백만 남은 제목은 nil로 보낸다 — 빈 문자열과 null이 둘 다 "제목 없음"이면 판정이 갈린다.
        #expect(PickTitle.normalized("   ") == nil)
        #expect(PickTitle.normalized("   여름밤 ") == "여름밤")
    }

    /// 두 축이 어떻게 나오든 유형이 하나로 정해지고, 행동 기반 판정과 같은 규칙을 쓴다.
    @Test func tasteQuizTypeMatchesBehaviorMapping() {
        #expect(DiggingType(selective: true, concentrated: true) == .purist)
        #expect(DiggingType(selective: true, concentrated: false) == .restlessCurator)
        #expect(DiggingType(selective: false, concentrated: true) == .loyalist)
        #expect(DiggingType(selective: false, concentrated: false) == .omnivore)

        // 유형 문항을 전부 첫 번째 선택지(까다로움/집중)로 찍으면 Purist.
        let allFirst = [Int](repeating: 0, count: TasteQuiz.questions.count)
        #expect(TasteQuiz.result(answers: allFirst).type == .purist)

        // 빈 답도 크래시 없이 가장 무난한 유형으로 떨어진다.
        #expect(TasteQuiz.result(answers: []).type == .omnivore)
        #expect(TasteQuiz.result(answers: []).genreNames.isEmpty)

        // 범위를 벗어난 답은 무시하고 나머지로 채점한다.
        #expect(TasteQuiz.result(answers: [99, -1]).genreNames.isEmpty)
    }

}
