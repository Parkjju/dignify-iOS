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

    // MARK: Users

    static var myProfile: Endpoint { Endpoint(method: .get, path: "/users/me") }

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
}

private extension Optional where Wrapped == String {
    /// nil이면 빈 배열, 값이 있으면 단일 쿼리 아이템. 커서 옵셔널 처리 중복 제거.
    func queryItems(name: String) -> [URLQueryItem] {
        map { [URLQueryItem(name: name, value: $0)] } ?? []
    }
}
