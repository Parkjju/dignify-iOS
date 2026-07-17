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
}
