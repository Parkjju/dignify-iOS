//
//  APIClient.swift
//  dignify
//
//  Created by 박경준 on 7/2/26.
//

import Foundation

// MARK: - Endpoint

/// 엔드포인트 하나를 표현하는 값 타입. 실제 엔드포인트 목록/DTO는 별도 파일에서 정의.
nonisolated struct Endpoint {
    enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    var method: Method
    var path: String                       // "/feed", "/tracks/12/hype" 등 (base URL 뒤)
    var query: [URLQueryItem] = []
    var body: Encodable? = nil
    var needsAuth: Bool = true             // false면 Bearer 미주입 (/auth/apple, /auth/refresh)
}

// MARK: - APIError

nonisolated enum APIError: Error {
    case unauthorized                      // refresh까지 실패 → 로그아웃 필요
    case server(code: String, message: String, status: Int)   // {code,message} 봉투
    case http(status: Int)                 // 봉투 없는 4xx/5xx
    case transport(Error)                  // 네트워크/타임아웃
    case decoding(Error)
}

private nonisolated struct ErrorEnvelope: Decodable { let code: String; let message: String }

// MARK: - APIClient

/// URLSession 기반 async/await 클라이언트.
/// 401 감지 시 /auth/refresh 후 원 요청을 1회 재시도한다 (single-flight).
actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore

    private var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?

    /// refresh까지 실패해 세션이 끊겼을 때 호출된다. AppSession이 .signedOut 전환에 사용.
    private var onAuthFailure: (@Sendable () -> Void)?

    init(baseURL: URL, session: URLSession = .shared, tokenStore: TokenStore = TokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        self.tokens = tokenStore.load()
    }

    func setOnAuthFailure(_ handler: @escaping @Sendable () -> Void) {
        onAuthFailure = handler
    }

    // 로그인/로그아웃이 외부에서 토큰을 갱신할 때 사용.
    func setTokens(_ tokens: AuthTokens?) {
        self.tokens = tokens
        if let tokens { tokenStore.save(tokens) } else { tokenStore.clear() }
    }

    var isAuthenticated: Bool { tokens != nil }

    /// 로그아웃/회원탈퇴 시 서버에 넘길 refresh token. 토큰 없으면 nil.
    var currentRefreshToken: String? { tokens?.refreshToken }

    // MARK: Send

    /// 응답 본문이 있는 요청.
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await perform(endpoint)
        do { return try JSON.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    /// 본문이 없는 요청(204/201 등). 상태 코드 검증만.
    func send(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: Core

    private func perform(_ endpoint: Endpoint, isRetry: Bool = false) async throws -> Data {
        let request = try buildRequest(endpoint)
        apiLog("→ \(endpoint.method.rawValue) \(endpoint.path)\(isRetry ? " (retry)" : "")")

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch {
            apiLog("✗ \(endpoint.path) transport: \(error.localizedDescription)")
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.http(status: -1) }
        apiLog("← \(http.statusCode) \(endpoint.path)")

        // 401 → refresh 후 1회 재시도. refresh 엔드포인트 자체의 401은 재시도 대상 아님.
        if http.statusCode == 401, endpoint.needsAuth, !isRetry {
            _ = try await performRefresh()
            return try await perform(endpoint, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { onAuthFailure?() }
            if let env = try? JSON.decoder.decode(ErrorEnvelope.self, from: data) {
                apiLog("✗ \(endpoint.path) \(http.statusCode) \(env.code): \(env.message)")
                if http.statusCode == 401 { throw APIError.unauthorized }
                throw APIError.server(code: env.code, message: env.message, status: http.statusCode)
            }
            apiLog("✗ \(endpoint.path) \(http.statusCode) (no envelope): \(String(data: data, encoding: .utf8) ?? "")")
            throw http.statusCode == 401 ? APIError.unauthorized : APIError.http(status: http.statusCode)
        }
        return data
    }

    private func buildRequest(_ endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = baseURL.path + endpoint.path   // "/v1" + "/feed" → "/v1/feed"
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let url = components?.url else { throw APIError.http(status: -1) }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSON.encoder.encode(AnyEncodable(body))
        }
        if endpoint.needsAuth, let access = tokens?.accessToken {
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Refresh (single-flight)

    /// 동시에 여러 요청이 401을 받아도 refresh는 한 번만 돈다. 나머지는 같은 Task 결과를 기다림.
    private func performRefresh() async throws -> AuthTokens {
        if let existing = refreshTask { return try await existing.value }

        let task = Task { try await self.doRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func doRefresh() async throws -> AuthTokens {
        guard let refreshToken = tokens?.refreshToken else {
            onAuthFailure?()
            throw APIError.unauthorized
        }
        let request = try buildRequest(.refresh(refreshToken: refreshToken))
        apiLog("→ POST /auth/refresh")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                apiLog("✗ /auth/refresh failed → 재로그인 필요")
                // 슬라이딩 윈도우 refresh 실패 → 재로그인 필요
                setTokens(nil)
                onAuthFailure?()
                throw APIError.unauthorized
            }
            apiLog("← 200 /auth/refresh (토큰 갱신)")
            // 응답의 새 refreshToken까지 반드시 저장 (rotation).
            let new = try JSON.decoder.decode(AuthTokens.self, from: data)
            setTokens(new)
            return new
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }
}

/// 네트워크 요청/응답 콘솔 로그. DEBUG 빌드에서만 출력, 릴리스는 no-op.
/// Xcode 콘솔에서 "[API]"로 필터.
private nonisolated func apiLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[API] \(message())")
    #endif
}

/// Encodable existential을 URLRequest body로 인코딩하기 위한 얇은 래퍼.
private nonisolated struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
