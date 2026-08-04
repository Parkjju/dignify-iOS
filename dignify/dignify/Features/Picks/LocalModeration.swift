import Foundation

/// 차단·신고 숨김은 전부 로컬이다. 서버엔 차단 테이블이 없고, 신고는 쌓이기만 한다(운영자가 SQL로 처리).
/// 값은 개행으로 이어붙인 한 문자열 — `@AppStorage`가 배열을 못 받아서다.
/// ponytail: 목록이 커질 일이 없다(내가 차단한 사람 수). 커지면 그때 JSON으로.
enum LocalModeration {
    static let blockedKey = "blockedNicknames"
    static let hiddenPicksKey = "hiddenPickIds"

    static func items(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init)
    }

    static func adding(_ item: String, to raw: String) -> String {
        var list = items(raw)
        guard !list.contains(item) else { return raw }
        list.append(item)
        return list.joined(separator: "\n")
    }

    static func removing(_ item: String, from raw: String) -> String {
        items(raw).filter { $0 != item }.joined(separator: "\n")
    }
}
