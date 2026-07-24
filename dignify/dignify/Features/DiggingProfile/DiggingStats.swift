import Foundation

/// Digging Profile 도메인 모델. 백엔드 `GET /users/me/stats`의 숫자만 담고,
/// 유형·격차 헤드라인·잠금 판정 등 "파생"은 전부 여기서 계산한다(백엔드는 라벨/문구 모름).
/// 임계값은 클라 상수 → 데이터 보고 튜닝해도 백엔드 재배포 없음.
struct DiggingStats {
    var distinctListenedCount: Int
    var hypeCount: Int
    var listenedByGenre: [Count]     // count 내림차순
    var hypedByGenre: [Count]
    var listenedByArtist: [Count]    // top 5
    var hypedByArtist: [Count]

    struct Count: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    // MARK: - 임계값 (클라 튜닝 지점)

    private static let minListens = 10
    private static let minHypes = 3
    private static let selectivityThreshold = 0.25   // 미만 = 까다로움(Curator)
    private static let breadthThreshold = 0.5        // top 장르 점유율 초과 = 집중(Devotee)

    // MARK: - 파생

    /// 유형 해제 조건 — 청취/하입 둘 다 충분해야 함(하입 행동도 유도).
    var isUnlocked: Bool {
        distinctListenedCount >= Self.minListens && hypeCount >= Self.minHypes
    }

    var type: DiggingType? {
        guard isUnlocked, distinctListenedCount > 0 else { return nil }
        let selective = Double(hypeCount) / Double(distinctListenedCount) < Self.selectivityThreshold
        let topShare = Double(listenedByGenre.first?.count ?? 0) / Double(distinctListenedCount)
        let concentrated = topShare > Self.breadthThreshold
        switch (selective, concentrated) {
        case (true, true):   return .purist
        case (true, false):  return .restlessCurator
        case (false, true):  return .loyalist
        case (false, false): return .omnivore
        }
    }

    /// 유형 라벨 뒤 향미("deep in Hip-Hop").
    var flavorGenre: String? { listenedByGenre.first?.name }

    /// 격차 헤드라인 — 파는 장르 vs 담는 장르. 데이터 부족이면 nil(숨김).
    var headline: String? {
        guard let dig = listenedByGenre.first?.name,
              let keep = hypedByGenre.first?.name else { return nil }
        return dig == keep
            ? String(localized: "\(keep), top to bottom.")
            : String(localized: "You listen to \(dig) the most — but \(keep) is what you keep.")
    }
}

/// 2축 4유형. 표시명/한 줄 설명은 여기(브랜드 카피).
enum DiggingType {
    case restlessCurator, purist, omnivore, loyalist

    var name: String {
        switch self {
        case .restlessCurator: return String(localized: "The Restless Curator")
        case .purist:          return String(localized: "The Purist")
        case .omnivore:        return String(localized: "The Omnivore")
        case .loyalist:        return String(localized: "The Loyalist")
        }
    }

    var blurb: String {
        switch self {
        case .restlessCurator: return String(localized: "You range across genres, but only a rare few make it in.")
        case .purist:          return String(localized: "One lane, dug deep — with standards to match.")
        case .omnivore:        return String(localized: "Everything's fair game, and you keep a lot of it.")
        case .loyalist:        return String(localized: "You know your sound and you stay loyal to it.")
        }
    }
}

// MARK: - Mock (프로토타입 전용)

extension DiggingStats {
    /// All time — 해제된 상태. Curator × Wanderer + 격차(Hip-Hop→Jazz).
    static let mockAllTime = DiggingStats(
        distinctListenedCount: 42,
        hypeCount: 8,
        listenedByGenre: [
            .init(name: "Hip-Hop", count: 18), .init(name: "R&B", count: 9),
            .init(name: "Jazz", count: 6), .init(name: "Electronic", count: 5),
            .init(name: "Pop", count: 4),
        ],
        hypedByGenre: [
            .init(name: "Jazz", count: 4), .init(name: "Hip-Hop", count: 2),
            .init(name: "R&B", count: 2),
        ],
        listenedByArtist: [
            .init(name: "MF DOOM", count: 6), .init(name: "Robert Glasper", count: 4),
            .init(name: "Kaytranada", count: 3), .init(name: "Alfa Mist", count: 3),
            .init(name: "SZA", count: 2),
        ],
        hypedByArtist: [
            .init(name: "Robert Glasper", count: 3), .init(name: "Alfa Mist", count: 2),
            .init(name: "MF DOOM", count: 1),
        ]
    )

    /// This week — 잠금 상태(하입 부족). 볼륨 페어는 그대로 노출됨을 보여줌.
    static let mockThisWeek = DiggingStats(
        distinctListenedCount: 8,
        hypeCount: 1,
        listenedByGenre: [
            .init(name: "Hip-Hop", count: 4), .init(name: "Jazz", count: 2),
            .init(name: "R&B", count: 2),
        ],
        hypedByGenre: [.init(name: "Jazz", count: 1)],
        listenedByArtist: [
            .init(name: "MF DOOM", count: 2), .init(name: "Alfa Mist", count: 2),
            .init(name: "SZA", count: 1),
        ],
        hypedByArtist: [.init(name: "Alfa Mist", count: 1)]
    )
}
