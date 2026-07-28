//
//  DTOs.swift
//  dignify
//
//  Created by 박경준 on 7/2/26.
//

import Foundation

/// 서버 wire 타입 모음 (openapi.yaml 스키마 그대로).
/// 도메인 모델(`Feed`, `Genre`)과 이름/구조가 달라 분리 — 도메인 매핑은 서비스/뷰모델 계층 책임.
/// ponytail: 응답 전용이라 대부분 Decodable만. 요청 바디는 Endpoints.swift에 fileprivate.
nonisolated enum API {

    // MARK: Auth
    // /auth/apple, /auth/refresh 응답(AuthTokenResponse)은 AuthTokens(TokenStore.swift) 재사용.

    // MARK: Genres

    struct Genre: Decodable {
        let genreId: Int
        let genreName: String
        /// 배포 순서 때문에 optional — 백엔드보다 앱이 먼저 나가도 장르 목록이 죽지 않게.
        /// 양쪽 배포가 안정되면 non-optional로 조여도 된다(FeedItem.genreName과 같은 이유).
        let genreNameEn: String?
    }

    struct GenresResponse: Decodable {
        let genres: [Genre]
    }

    // MARK: Feed

    struct FeedItem: Decodable {
        let trackId: Int
        let trackName: String
        let artistName: String
        let artworkUrl: String
        let previewUrl: String
        let trackViewUrl: String
        let isHyped: Bool
        /// 이 트랙이 왜 떴는지 보여주는 장르 라벨(서버가 Accept-Language로 현지화).
        /// optional인 이유는 배포 순서 — 백엔드보다 앱이 먼저 나가도 피드가 죽지 않게.
        /// 양쪽 배포가 안정되면 non-optional로 조여도 된다.
        let genreName: String?
        /// 같은 장르가 로케일별로 다른 값이 되면 분석에서 집계가 쪼개진다(Rock/록).
        /// 화면엔 안 쓰고 이벤트 프로퍼티로만 나간다. optional인 이유는 genreName과 동일.
        let genreNameEn: String?
    }

    /// 이번 주 큐레이션 세트. setKey는 세트가 교체될 때만 바뀌는 식별자로,
    /// 같은 세트를 이미 다 본 유저에게 다시 앞세우지 않기 위해 로컬에 저장한다.
    struct CurationResponse: Decodable {
        let setKey: String
        let items: [FeedItem]
    }

    /// 피드/검색 공통 응답. nextCursor 없으면 hasMore=false (피드 소진).
    struct FeedResponse: Decodable {
        let items: [FeedItem]
        let nextCursor: String?
        let hasMore: Bool
        /// 이 페이지가 유저 장르 풀을 소진하고 장르 무관 트랙으로 채워졌는지. 검색 응답엔 없어 optional.
        let genreExhausted: Bool?
    }

    // MARK: Tracks

    struct TrackDetail: Decodable {
        let trackId: Int
        let trackName: String
        let artistName: String
        let collectionName: String
        let artworkUrl: String
        let trackViewUrl: String
        let releaseDate: String   // date-only("yyyy-MM-dd") — iso8601 파싱 안 되므로 String 유지
        let genreName: String
        let firstHypers: [UserSummary]   // 가장 먼저 하입한 순 최대 5명
    }

    struct UserSummary: Decodable {
        let userId: Int
        let nickname: String
        /// 하입한 시각. 백엔드 배포 전엔 필드가 없어 nil(옵셔널이라 디코딩 안 깨짐).
        let hypedAt: Date?
    }

    // MARK: Users

    struct UserProfile: Decodable {
        let nickname: String
        let isOnboardingComplete: Bool
        let genres: [ProfileGenre]

        struct ProfileGenre: Decodable {
            /// 서버는 원래 보내고 있었는데 앱이 안 읽고 있었다. 장르 대조는 이걸로 한다 —
            /// 이름은 로케일마다 달라져서 엔드포인트 간에 문자열이 어긋날 수 있다.
            let genreId: Int
            let genreName: String
        }
    }

    struct NicknameResponse: Decodable {
        let nickname: String
    }

    struct HypeItem: Decodable {
        let userHypeTrackId: Int
        let trackId: Int
        let trackName: String
        let artistName: String
        let artworkUrl: String
        let previewUrl: String
        let hypedAt: Date   // date-time(ISO8601) — 클라 날짜 섹션 그룹핑용
    }

    /// 마이페이지 하입 목록. 커서는 마지막 userHypeTrackId(Int).
    struct HypeListResponse: Decodable {
        let items: [HypeItem]
        let nextCursor: Int?
    }

    /// 디깅 프로필 통계. 개수는 전부 재생 횟수가 아니라 **곡 종류 수**(COUNT DISTINCT).
    /// 유형·격차 헤드라인·잠금 판정은 서버가 모르고 클라(`DiggingStats`)가 이 숫자로 계산한다.
    /// 응답의 `range`는 요청값 그대로라 쓰지 않는다.
    struct UserStats: Decodable {
        let distinctListenedCount: Int
        let hypeCount: Int
        /// 전체 장르, count 내림차순.
        let listenedByGenre: [GenreCount]
        let hypedByGenre: [GenreCount]
        /// 상위 5개만 — 합계 용도로 쓰면 안 됨.
        let listenedByArtist: [ArtistCount]
        let hypedByArtist: [ArtistCount]

        struct GenreCount: Decodable {
            let genreName: String   // Accept-Language 로케일(ko/en)
            let count: Int
        }

        struct ArtistCount: Decodable {
            let artistName: String
            let count: Int
        }
    }

    /// 아티스트 요청 처리 상태. 서버가 새 값을 추가해도 깨지지 않게 미지 값은 pending으로 폴백.
    enum RequestStatus: String, Decodable {
        case pending = "PENDING", added = "ADDED", canceled = "CANCELED"
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = RequestStatus(rawValue: raw) ?? .pending
        }
    }

    struct ArtistRequest: Decodable, Identifiable {
        let id: Int
        let artistName: String
        let status: RequestStatus
        let cancelReason: String?   // status == .canceled 일 때만 채워짐
        let createdAt: Date         // date-time(ISO8601)
    }

    /// 내 요청 히스토리(최신순). 현실적으로 소량이라 페이지네이션 없이 전체를 준다.
    struct ArtistRequestListResponse: Decodable {
        let items: [ArtistRequest]
    }
}
