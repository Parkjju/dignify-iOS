import Foundation

/// 장르 한 줄 설명.
///
/// 음악을 잘 모르는 사람이 "R&B/Soul이 뭔데"에서 막히지 않을 만큼만 준다.
/// 음악사·악기 편성 강의는 하지 않는다 — 온보딩에서 읽을 분량이 아니고, 앱이 무거워진다.
/// 한 줄, 반말체, 판단에 필요한 것만.
///
/// ponytail: 서버 컬럼이 아니라 클라 상수. 카피 튜닝에 백엔드 배포가 필요 없고,
/// 장르가 늘어도 매칭 실패 시 설명만 빠지고 화면은 멀쩡하다(아래 default).
enum GenreGuide {

    /// 서버 원문(영문) 장르명 → 한 줄 설명. 모르는 장르는 nil(설명 없이 샘플만).
    /// 키는 iTunes `primaryGenreName` 원문이라 `genres.genre_name_en`과 정확히 일치해야 한다.
    static func blurb(for nameEn: String?) -> String? {
        switch nameEn {
        case "Hip-Hop/Rap":
            return String(localized: "Beats and rhymes. The words are doing the work.")
        case "Rock":
            return String(localized: "Guitars, drums, and volume. Loud or moody, take your pick.")
        case "Pop":
            return String(localized: "Big choruses built to stick after one listen.")
        case "Jazz":
            return String(localized: "Improvised on the spot — the same song is never quite the same twice.")
        case "Dance":
            return String(localized: "Made for a floor. Steady kick, no reason to stop moving.")
        case "Country":
            return String(localized: "Someone telling you a story, guitar in hand.")
        case "R&B/Soul":
            return String(localized: "Smooth grooves and voices that carry the whole thing.")
        case "Electronic":
            return String(localized: "Built from synths and machines. Often no vocals at all.")
        case "K-Pop":
            return String(localized: "Packed with hooks, switches lanes mid-song, made to be watched too.")
        case "Latin":
            return String(localized: "Percussion you feel before you hear. Reggaetón, salsa, and everything nearby.")
        case "CCM":
            return String(localized: "Worship songs with pop production — written for a room singing along.")
        // 아래 셋은 카탈로그가 얇다(2026-07-27 기준 12/7/2곡). 그래도 /genres에 나오므로
        // 직접 고르는 화면에서 설명 없이 뜨지 않게 채워 둔다. 퀴즈는 이들을 추천하지 않는다
        // — 곡이 몇 개뿐이라 추천해봐야 피드가 바로 마른다.
        case "Alternative":
            return String(localized: "Rock that ducks the mainstream. Not big on following the rules.")
        case "Bass":
            return String(localized: "The low end is the whole point. Best where the speakers can take it.")
        case "Dubstep":
            return String(localized: "Everything builds toward the moment the bass drops.")
        default:
            return nil
        }
    }
}
