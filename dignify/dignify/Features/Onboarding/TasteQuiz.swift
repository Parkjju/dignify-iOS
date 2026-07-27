import Foundation

/// 온보딩 취향 테스트의 문항·채점. 순수 로직이라 뷰 없이 테스트된다.
///
/// 두 가지를 동시에 뽑는다:
///  - **유형** — 선택성·폭 2축(각 3문항, 홀수라 동점 없음) → 기존 `DiggingType` 4유형.
///  - **추천 장르** — 별도 5문항의 장르 점수 합 상위 3개.
///
/// 유형에서 장르를 유추하지 않는다. Purist라고 재즈를 좋아할 이유가 없어서,
/// 장르는 장르 문항에서만 나온다.
///
/// 점수표는 전수 시뮬레이션(4^4×5 = 1280 조합)으로 균형을 맞췄다 —
/// 모든 장르가 top3 도달 가능하고, 어느 장르도 과반을 먹지 않는다.
/// 회귀는 `tasteQuizMappingIsBalanced` 테스트가 잡는다.
enum TasteQuiz {

    struct Option {
        let label: String
        /// genreNameEn → 점수. 유형 문항은 비어 있다.
        var genres: [String: Int] = [:]
        /// 선택성 축 기여(true = 까다로움). nil이면 이 축과 무관한 문항.
        var selective: Bool?
        /// 폭 축 기여(true = 집중). nil이면 이 축과 무관한 문항.
        var concentrated: Bool?

        init(_ label: String, genres: [String: Int] = [:], selective: Bool? = nil, concentrated: Bool? = nil) {
            self.label = label
            self.genres = genres
            self.selective = selective
            self.concentrated = concentrated
        }
    }

    struct Question {
        let prompt: String
        let options: [Option]
    }

    struct Result {
        let type: DiggingType
        /// 추천 장르(genreNameEn) 상위 3개, 점수 내림차순.
        let genreNames: [String]
    }

    /// 퀴즈가 추천할 수 있는 장르 전체 + 동점 처리 순서(카탈로그 트랙 수 내림차순 —
    /// 같은 점수면 피드가 더 안 마르는 쪽을 준다). 2026-07-27 프로덕션 기준.
    ///
    /// `Alternative`(12곡) · `Bass`(7곡) · `Dubstep`(2곡)은 일부러 뺐다. 고르자마자
    /// 피드가 말라 GENERAL 폴백으로 넘어가서다. 직접 고르는 화면에는 그대로 노출되고
    /// 설명도 `GenreGuide`에 있다.
    /// **카탈로그가 차면 여기에 추가하고** 아래 문항 배점에도 넣을 것 —
    /// 목록에만 넣고 배점을 안 주면 `tasteQuizMappingIsBalanced`가 "도달 불가"로 잡는다.
    static let catalogOrder = [
        "Hip-Hop/Rap", "Rock", "Pop", "Jazz", "Dance", "Country",
        "R&B/Soul", "Electronic", "K-Pop", "Latin", "CCM",
    ]

    // MARK: - 문항

    static let questions: [Question] = genreQuestions + typeQuestions

    /// 장르 문항이 먼저다 — 구체적이고 답하기 쉬워서 이탈이 덜하다.
    private static let genreQuestions: [Question] = [
        Question(prompt: String(localized: "When do you turn it all the way up?"), options: [
            Option(String(localized: "Working out"), genres: ["Hip-Hop/Rap": 3, "Dance": 3, "Electronic": 2]),
            Option(String(localized: "Driving"), genres: ["Rock": 3, "Country": 3, "Pop": 2]),
            Option(String(localized: "Working or studying"), genres: ["Jazz": 3, "Electronic": 2, "R&B/Soul": 2]),
            Option(String(localized: "Hanging out with people"), genres: ["Latin": 3, "Dance": 2, "K-Pop": 2]),
        ]),
        Question(prompt: String(localized: "What hits you first in a song?"), options: [
            Option(String(localized: "The flow"), genres: ["Hip-Hop/Rap": 4]),
            Option(String(localized: "The story in the lyrics"), genres: ["Country": 3, "CCM": 2, "Hip-Hop/Rap": 1]),
            Option(String(localized: "The voice itself"), genres: ["R&B/Soul": 3, "Pop": 2, "K-Pop": 1]),
            Option(String(localized: "Guitars and drums locking in"), genres: ["Rock": 4, "Country": 1]),
            Option(String(localized: "The beat and the synths"), genres: ["Electronic": 3, "Dance": 2, "K-Pop": 1]),
        ]),
        Question(prompt: String(localized: "Pick your kind of night"), options: [
            Option(String(localized: "A club until sunrise"), genres: ["Dance": 3, "Electronic": 2, "Latin": 2]),
            Option(String(localized: "Front row at a live show"), genres: ["Rock": 3, "K-Pop": 2]),
            Option(String(localized: "A corner seat at a jazz bar"), genres: ["Jazz": 3, "R&B/Soul": 3]),
            Option(String(localized: "Home alone, volume low"), genres: ["CCM": 3, "R&B/Soul": 2, "Country": 2, "Pop": 1]),
        ]),
        Question(prompt: String(localized: "Lyrics that aren't in English?"), options: [
            Option(String(localized: "I listen to Korean tracks a lot"), genres: ["K-Pop": 4]),
            Option(String(localized: "Spanish? If it grooves, sure"), genres: ["Latin": 4]),
            Option(String(localized: "English is what I'm used to"), genres: ["Pop": 2, "Rock": 1, "Hip-Hop/Rap": 1, "Country": 1]),
            Option(String(localized: "No lyrics at all works too"), genres: ["Electronic": 3, "Jazz": 3]),
        ]),
        Question(prompt: String(localized: "What do you want music to do for you?"), options: [
            Option(String(localized: "Get me hyped"), genres: ["Dance": 2, "Hip-Hop/Rap": 2, "K-Pop": 2]),
            Option(String(localized: "Sit with me"), genres: ["CCM": 3, "R&B/Soul": 3, "Country": 1]),
            Option(String(localized: "Pull me in and shut everything else out"), genres: ["Jazz": 2, "Electronic": 2, "Rock": 1]),
            Option(String(localized: "Just put me in a good mood"), genres: ["Pop": 3, "Latin": 1, "K-Pop": 1]),
        ]),
    ]

    /// 선택성 3문항 + 폭 3문항. 각 축 홀수라 동점이 안 난다.
    private static let typeQuestions: [Question] = [
        Question(prompt: String(localized: "Your playlist is..."), options: [
            Option(String(localized: "30 tracks, all earned"), selective: true),
            Option(String(localized: "300 tracks, sort it out later"), selective: false),
        ]),
        Question(prompt: String(localized: "A track comes on and it's not doing it for you"), options: [
            Option(String(localized: "Skipped in five seconds"), selective: true),
            Option(String(localized: "Eh, I'll let it ride"), selective: false),
        ]),
        Question(prompt: String(localized: "Saving a song you just found"), options: [
            Option(String(localized: "Give it a few more listens first"), selective: true),
            Option(String(localized: "In it goes"), selective: false),
        ]),
        Question(prompt: String(localized: "You find an artist you love"), options: [
            Option(String(localized: "Straight through the whole discography"), concentrated: true),
            Option(String(localized: "Off to find someone who sounds like them"), concentrated: false),
        ]),
        Question(prompt: String(localized: "Someone recommends a genre you never listen to"), options: [
            Option(String(localized: "Probably not my thing"), concentrated: true),
            Option(String(localized: "Might as well press play"), concentrated: false),
        ]),
        Question(prompt: String(localized: "Scroll back through what you played this week"), options: [
            Option(String(localized: "Same lane the whole way"), concentrated: true),
            Option(String(localized: "All over the place"), concentrated: false),
        ]),
    ]

    // MARK: - 채점

    /// `answers[i]` = i번 문항에서 고른 선택지 인덱스. 범위를 벗어난 답은 무시한다.
    static func result(answers: [Int]) -> Result {
        var scores: [String: Int] = [:]
        var selectiveVotes = 0
        var concentratedVotes = 0

        for (i, choice) in answers.enumerated() {
            guard questions.indices.contains(i),
                  questions[i].options.indices.contains(choice) else { continue }
            let option = questions[i].options[choice]
            for (genre, points) in option.genres { scores[genre, default: 0] += points }
            if let s = option.selective { selectiveVotes += s ? 1 : -1 }
            if let c = option.concentrated { concentratedVotes += c ? 1 : -1 }
        }

        // 축이 0표(전부 미응답)면 관대함/폭넓음 = Omnivore로 떨어진다. 가장 무난한 기본값.
        let type = DiggingType(selective: selectiveVotes > 0, concentrated: concentratedVotes > 0)

        let ranked = scores.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return catalogRank(lhs.key) < catalogRank(rhs.key)
        }
        return Result(type: type, genreNames: ranked.prefix(3).map(\.key))
    }

    /// 카탈로그에 없는 장르는 맨 뒤로.
    static func catalogRank(_ name: String) -> Int {
        catalogOrder.firstIndex(of: name) ?? catalogOrder.count
    }
}
