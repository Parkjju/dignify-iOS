//
//  TokenStore.swift
//  dignify
//
//  Created by 박경준 on 7/2/26.
//

import Foundation
import Security

/// 서버가 발급하는 인증 토큰 묶음. `/auth/apple`, `/auth/refresh` 응답(AuthTokenResponse) 그대로.
nonisolated struct AuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
}

/// refreshToken까지 포함해 Keychain에 단일 blob으로 저장한다.
/// accessToken은 APIClient가 메모리 캐시로도 들고 있지만, 앱 재실행 시 세션 복원을 위해 함께 보관.
/// ponytail: 필드별로 쪼개지 않고 JSON 한 덩어리. 항목이 늘면 그때 분리.
nonisolated struct TokenStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.rta.dignify"
    private let account = "authTokens"

    func load() -> AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let tokens = try? JSON.decoder.decode(AuthTokens.self, from: data)
        else { return nil }
        return tokens
    }

    func save(_ tokens: AuthTokens) {
        guard let data = try? JSON.encoder.encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // upsert: 있으면 갱신, 없으면 추가
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 서버 date-time(ISO8601) 인/디코딩용 공용 코더.
/// ponytail: 매 호출 새 인스턴스 — 비-Sendable static 공유를 피해 어느 액터에서든 안전.
nonisolated enum JSON {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        // Spring이 Instant를 소수점 초 붙여 직렬화(예 "…:56.123456Z")하는데
        // 기본 .iso8601 포매터는 소수점 초를 못 읽는다. 둘 다 시도해서 파싱.
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ISO8601 날짜 파싱 실패: \(s)"))
            }
            return date
        }
        return d
    }
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
