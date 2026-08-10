import Foundation
import Testing
@testable import dignify

/// 하입 목록은 "화면은 멀쩡한데 데이터가 조용히 잘리는" 부류라 눈으로 못 잡는다.
/// 1.0.9에서 실제로 페이지네이션이 죽어 첫 10개 뒤가 안 보였다 — 그 회귀를 여기서 막는다.
struct HypeGroupingTests {

    /// 백엔드는 `userHypeTrackId` 내림차순(최신순)으로 준다. 테스트도 같은 순서로 만든다.
    private static func items(_ spec: [(day: Int, count: Int)], startId: Int = 1000) -> [API.HypeItem] {
        var id = startId
        var out: [API.HypeItem] = []
        for (day, count) in spec {
            for _ in 0..<count {
                id -= 1
                out.append(API.HypeItem(
                    userHypeTrackId: id, trackId: id, trackName: "t\(id)", artistName: "a\(id)",
                    artworkUrl: "https://example.com/\(id)/100x100bb.jpg",
                    previewUrl: "https://example.com/\(id).m4a",
                    // day는 "며칠 전". 시각을 정오로 고정해 로컬 타임존이 날짜를 넘기지 않게 한다.
                    hypedAt: Calendar.current.date(byAdding: .day, value: -day,
                                                   to: Calendar.current.startOfDay(for: Date())
                                                       .addingTimeInterval(12 * 3600))!))
            }
        }
        return out
    }

    @Test func groupsKeepServerOrderAndSplitByDay() {
        let groups = HypeGrouping.dayGroups(Self.items([(0, 3), (2, 1), (5, 2)]))
        #expect(groups.map(\.tracks.count) == [3, 1, 2])
        // 최신 그룹이 먼저 — 서버 순서를 재정렬하지 않는다.
        #expect(groups[0].id > groups[1].id)
        #expect(groups[1].id > groups[2].id)
    }

    @Test func previewLimitsCutGroupsAndTracks() {
        let items = Self.items([(0, 8), (1, 8), (2, 8)])
        let preview = HypeGrouping.dayGroups(items, maxGroups: 2, perDayLimit: 3)
        #expect(preview.count == 2)
        #expect(preview.allSatisfy { $0.tracks.count == 3 })
        // 잘라낸 건 표시뿐 — 원본은 그대로여야 다음 페이지 판정이 맞는다.
        #expect(items.count == 24)
    }

    /// 이게 1.0.9 버그 그 자체다. 새 페이지 10개가 전부 같은 날이면 마지막 날짜 그룹의
    /// id(startOfDay)는 안 바뀐다 → 그룹 id로 페이지를 트리거하면 두 번째 페이지에서 멈춘다.
    /// 마지막 트랙 id는 페이지마다 반드시 바뀐다.
    @Test func pagingAnchorChangesEvenWhenTheWholePageIsOneDay() {
        let page1 = Self.items([(0, 10)])
        let page2 = Self.items([(0, 10)], startId: 900)   // 같은 날, 더 오래된 id
        let combined = page1 + page2

        // 날짜 그룹 id는 그대로 — 그룹을 기준으로 삼으면 여기서 페이지네이션이 죽는다.
        #expect(HypeGrouping.dayGroups(page1).last?.id == HypeGrouping.dayGroups(combined).last?.id)
        #expect(HypeGrouping.dayGroups(combined).count == 1)

        // 트랙 기준이면 페이지마다 값이 바뀌어 다음 요청이 이어진다.
        #expect(HypeGrouping.pagingAnchor(page1) != HypeGrouping.pagingAnchor(combined))
        #expect(HypeGrouping.pagingAnchor(combined) == combined.last?.userHypeTrackId)
        #expect(HypeGrouping.pagingAnchor([]) == nil)
    }

    @Test func hasMoreCoversCursorDaysAndPerDayOverflow() {
        let fits = Self.items([(0, 2), (1, 2)])
        #expect(HypeGrouping.hasMore(fits, cursor: nil, maxGroups: 3, perDayLimit: 5) == false)
        // 커서가 남아 있으면 화면에 다 보여도 더 있다.
        #expect(HypeGrouping.hasMore(fits, cursor: 42, maxGroups: 3, perDayLimit: 5) == true)
        // 미리보기 날짜 수 초과.
        #expect(HypeGrouping.hasMore(Self.items([(0, 1), (1, 1), (2, 1), (3, 1)]),
                                     cursor: nil, maxGroups: 3, perDayLimit: 5) == true)
        // 날짜 수는 괜찮지만 하루 안에서 넘침 — 이걸 빼면 See all이 안 뜬다.
        #expect(HypeGrouping.hasMore(Self.items([(0, 9)]),
                                     cursor: nil, maxGroups: 3, perDayLimit: 5) == true)
        #expect(HypeGrouping.hasMore([], cursor: nil, maxGroups: 3, perDayLimit: 5) == false)
    }
}

/// 유형 판정은 임계값 상수 몇 개로 갈린다. 숫자를 만지면 여기가 먼저 깨져야 한다.
struct DiggingStatsTests {

    private static func stats(listened: Int, hypes: Int,
                              topGenre: Int = 0, keepGenre: String? = nil) -> DiggingStats {
        DiggingStats(
            distinctListenedCount: listened,
            hypeCount: hypes,
            listenedByGenre: topGenre > 0 ? [DiggingStats.Count(name: "Hip-Hop/Rap", count: topGenre)] : [],
            hypedByGenre: keepGenre.map { [DiggingStats.Count(name: $0, count: 1)] } ?? [],
            listenedByArtist: [],
            hypedByArtist: [])
    }

    @Test func typeStaysLockedUntilBothCountsClear() {
        // 청취만 많고 하입이 없으면 잠김 — 유형이 뜨면 안 된다.
        #expect(Self.stats(listened: 50, hypes: 2, topGenre: 40).type == nil)
        #expect(Self.stats(listened: 9, hypes: 10, topGenre: 5).type == nil)
        #expect(Self.stats(listened: 10, hypes: 3, topGenre: 6).isUnlocked)
        // 0으로 나누는 경로가 없어야 한다.
        #expect(Self.stats(listened: 0, hypes: 0).type == nil)
    }

    @Test func typeAxesMatchThresholds() {
        // 하입/청취 < 0.25 = 까다로움, top 장르 점유율 > 0.5 = 집중.
        #expect(Self.stats(listened: 100, hypes: 10, topGenre: 80).type == .purist)
        #expect(Self.stats(listened: 100, hypes: 10, topGenre: 20).type == .restlessCurator)
        #expect(Self.stats(listened: 100, hypes: 60, topGenre: 80).type == .loyalist)
        #expect(Self.stats(listened: 100, hypes: 60, topGenre: 20).type == .omnivore)
        // 경계값: 정확히 0.25와 0.5는 각각 "안 까다로움", "안 집중"이다.
        #expect(Self.stats(listened: 100, hypes: 25, topGenre: 50).type == .omnivore)
    }

    @Test func headlineHidesWhenEitherSideIsEmpty() {
        #expect(Self.stats(listened: 100, hypes: 10, topGenre: 50).headline == nil)   // 담은 장르 없음
        #expect(Self.stats(listened: 100, hypes: 10, keepGenre: "Jazz").headline == nil)   // 판 장르 없음
        let same = Self.stats(listened: 100, hypes: 10, topGenre: 50, keepGenre: "Hip-Hop/Rap")
        let gap = Self.stats(listened: 100, hypes: 10, topGenre: 50, keepGenre: "Jazz")
        // 같은 장르면 격차 문구가 아니라 한 줄짜리 문구로 갈린다.
        #expect(same.headline != gap.headline)
        #expect(gap.headline?.contains("Jazz") == true)
    }
}

struct ClientRuleTests {

    /// 백엔드 @Pattern과 같은 규칙이어야 한다. 어긋나면 서버에서 400으로 튕긴다.
    @Test func nicknameRuleMatchesBackendPattern() {
        #expect(Nickname.isValid("parkjju"))
        #expect(Nickname.isValid("박경준_2"))
        #expect(Nickname.isValid(String(repeating: "a", count: 20)))
        #expect(!Nickname.isValid(""))
        #expect(!Nickname.isValid(String(repeating: "a", count: 21)))
        #expect(!Nickname.isValid("park jju"))      // 공백
        #expect(!Nickname.isValid("park.jju"))      // 기호
        #expect(!Nickname.isValid("park\njju"))     // 개행 — 정규식 앵커가 줄 단위면 여기서 샌다
        #expect(!Nickname.isValid("파크😀"))         // 이모지
        #expect(!Nickname.isValid("ㅋㅋㅋ"))          // 자모 단독은 가-힣 범위 밖
    }

    /// 사이즈 세그먼트만 바꿔야 한다. 잘못 바꾸면 이미지가 깨지는 게 아니라
    /// 그냥 작은 이미지가 흐리게 떠서 눈으로 놓친다.
    @Test func artworkUpsizeReplacesOnlyTheSizeSegment() {
        let url = "https://is1-ssl.mzstatic.com/image/thumb/Music/ab/cd/ef/100x100bb.jpg"
        #expect(url.itunesArtworkURL(size: 600)?.absoluteString
                == "https://is1-ssl.mzstatic.com/image/thumb/Music/ab/cd/ef/600x600bb.jpg")
        // 소스가 100×100이 아닌 것도 있다.
        #expect("https://x.com/a/170x170bb.jpg".itunesArtworkURL(size: 600)?.absoluteString
                == "https://x.com/a/600x600bb.jpg")
        // 사이즈 세그먼트가 없으면 원본 그대로.
        #expect("https://x.com/a/cover.jpg".itunesArtworkURL(size: 600)?.absoluteString
                == "https://x.com/a/cover.jpg")
        #expect("".itunesArtworkURL(size: 600) == nil)
    }

    /// 차단 목록은 개행으로 이어붙인 한 문자열이라 중복·빈 줄이 조용히 쌓이기 쉽다.
    @Test func blockListAddsWithoutDuplicates() {
        var raw = ""
        raw = LocalModeration.adding("spammer", to: raw)
        raw = LocalModeration.adding("spammer", to: raw)     // 중복은 무시.
        raw = LocalModeration.adding("troll", to: raw)
        #expect(LocalModeration.items(raw) == ["spammer", "troll"])

        raw = LocalModeration.removing("spammer", from: raw)
        #expect(LocalModeration.items(raw) == ["troll"])
        // 없는 값을 지워도 목록이 망가지지 않는다.
        #expect(LocalModeration.items(LocalModeration.removing("nobody", from: raw)) == ["troll"])
        // 전부 지우면 빈 문자열 — 빈 줄 하나가 남으면 "이름 없는 차단"이 생긴다.
        #expect(LocalModeration.items(LocalModeration.removing("troll", from: raw)).isEmpty)
    }
}
