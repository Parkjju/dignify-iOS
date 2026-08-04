//
//  Endpoints.swift
//  dignify
//
//  Created by 박경준 on 7/2/26.
//

import Foundation

// 요청 바디 (이 파일에서만 사용).
private nonisolated struct IdentityTokenBody: Encodable { let identityToken: String }
private nonisolated struct RefreshTokenBody: Encodable { let refreshToken: String }
private nonisolated struct NicknameBody: Encodable { let nickname: String }
private nonisolated struct GenreIdsBody: Encodable { let genreIds: [Int] }
private nonisolated struct ArtistRequestBody: Encodable { let artistName: String }
private nonisolated struct DeviceTokenBody: Encodable { let token: String; let environment: String; let timeZone: String }
private nonisolated struct PickBody: Encodable { let title: String?; let trackIds: [Int] }
private nonisolated struct ReactionBody: Encodable { let emoji: String }
private nonisolated struct ReportBody: Encodable { let pickId: Int; let reason: String }

/// openapi.yaml 14개 엔드포인트 팩토리. 호출부: `client.send(.feed(cursor: c), as: API.FeedResponse.self)`
nonisolated extension Endpoint {

    // MARK: Auth

    static func appleSignIn(identityToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/apple",
                 body: IdentityTokenBody(identityToken: identityToken), needsAuth: false)
    }

    static func refresh(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/refresh",
                 body: RefreshTokenBody(refreshToken: refreshToken), needsAuth: false)
    }

    static func logout(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/logout",
                 body: RefreshTokenBody(refreshToken: refreshToken))
    }

    static func withdraw(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "/auth/withdraw",
                 body: RefreshTokenBody(refreshToken: refreshToken))
    }

    // MARK: Genres

    static var genres: Endpoint { Endpoint(method: .get, path: "/genres") }

    // MARK: Feed

    static func feed(cursor: String? = nil) -> Endpoint {
        Endpoint(method: .get, path: "/feed", query: cursor.queryItems(name: "cursor"))
    }

    /// 이번 주 큐레이션 세트. 전 유저 동일 내용이라 개인화 파라미터도 커서도 없다.
    static var curation: Endpoint { Endpoint(method: .get, path: "/feed/curation") }

    static func search(query: String, cursor: String? = nil) -> Endpoint {
        var items = [URLQueryItem(name: "q", value: query)]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return Endpoint(method: .get, path: "/feed/search", query: items)
    }

    // MARK: Tracks

    static func trackDetail(id: Int) -> Endpoint {
        Endpoint(method: .get, path: "/tracks/\(id)")
    }

    static func hype(trackId: Int) -> Endpoint {
        Endpoint(method: .post, path: "/tracks/\(trackId)/hype")
    }

    static func unhype(trackId: Int) -> Endpoint {
        Endpoint(method: .delete, path: "/tracks/\(trackId)/hype")
    }

    static func listen(trackId: Int) -> Endpoint {
        Endpoint(method: .post, path: "/tracks/\(trackId)/listen")
    }

    static func requestArtist(artistName: String) -> Endpoint {
        Endpoint(method: .post, path: "/artist-requests", body: ArtistRequestBody(artistName: artistName))
    }

    static var artistRequests: Endpoint { Endpoint(method: .get, path: "/artist-requests") }

    static func deleteArtistRequest(id: Int) -> Endpoint {
        Endpoint(method: .delete, path: "/artist-requests/\(id)")
    }

    // MARK: Picks

    static func picks(cursor: String? = nil) -> Endpoint {
        Endpoint(method: .get, path: "/picks", query: cursor.queryItems(name: "cursor"))
    }

    /// title은 trim 후 빈 값이면 nil로 넘긴다 — 빈 문자열과 null이 둘 다 "제목 없음"이면
    /// 폴백 판정이 두 갈래로 갈린다.
    static func createPick(title: String?, trackIds: [Int]) -> Endpoint {
        Endpoint(method: .post, path: "/picks", body: PickBody(title: title, trackIds: trackIds))
    }

    static func pickDetail(id: Int) -> Endpoint {
        Endpoint(method: .get, path: "/picks/\(id)")
    }

    static func deletePick(id: Int) -> Endpoint {
        Endpoint(method: .delete, path: "/picks/\(id)")
    }

    static func reactPick(id: Int, emoji: String) -> Endpoint {
        Endpoint(method: .put, path: "/picks/\(id)/reaction", body: ReactionBody(emoji: emoji))
    }

    static func unreactPick(id: Int) -> Endpoint {
        Endpoint(method: .delete, path: "/picks/\(id)/reaction")
    }

    static func reportPick(id: Int, reason: String) -> Endpoint {
        Endpoint(method: .post, path: "/reports", body: ReportBody(pickId: id, reason: reason))
    }

    // MARK: Users

    static var myProfile: Endpoint { Endpoint(method: .get, path: "/users/me") }

    static func deviceToken(token: String, environment: String, timeZone: String) -> Endpoint {
        Endpoint(method: .post, path: "/users/me/device-token",
                 body: DeviceTokenBody(token: token, environment: environment, timeZone: timeZone))
    }

    static func updateNickname(_ nickname: String) -> Endpoint {
        Endpoint(method: .patch, path: "/users/me/nickname", body: NicknameBody(nickname: nickname))
    }

    static var completeOnboarding: Endpoint {
        Endpoint(method: .post, path: "/users/me/onboarding/complete")
    }

    static func updateGenres(ids: [Int]) -> Endpoint {
        Endpoint(method: .put, path: "/users/me/genres", body: GenreIdsBody(genreIds: ids))
    }

    static func myHypes(cursor: Int? = nil) -> Endpoint {
        Endpoint(method: .get, path: "/users/me/hypes",
                 query: cursor.map(String.init).queryItems(name: "cursor"))
    }

    /// range: "all"(전체) | "week"(최근 7일). 그 외 값은 서버가 전체로 처리.
    static func myStats(range: String) -> Endpoint {
        Endpoint(method: .get, path: "/users/me/stats",
                 query: [URLQueryItem(name: "range", value: range)])
    }
}

// 호출부(Endpoint 팩토리)가 전부 nonisolated라 이쪽도 격리 밖이어야 한다
// — 이 모듈은 "Main Actor by default"라 안 붙이면 MainActor로 딸려 들어간다.
private nonisolated extension Optional where Wrapped == String {
    /// nil이면 빈 배열, 값이 있으면 단일 쿼리 아이템. 커서 옵셔널 처리 중복 제거.
    func queryItems(name: String) -> [URLQueryItem] {
        map { [URLQueryItem(name: name, value: $0)] } ?? []
    }
}
