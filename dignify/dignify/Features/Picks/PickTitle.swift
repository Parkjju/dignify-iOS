import SwiftUI

/// 제목을 비운 픽의 표시 제목을 클라에서 조립한다.
/// 서버에 저장하지 않는 이유: ①게시 시점 로케일로 굳어 영어 유저가 한국어를 본다
/// ②선곡에서 파생되는 중복값 ③곡이 비활성화되면 틀린 말이 된다.
/// 작성 화면의 플레이스홀더도 같은 문자열을 쓴다 — 비우면 실제로 나올 제목을 미리 보여준다.
enum PickTitle {
    /// 입력 필드 상한. Postgres varchar(120)는 code point로 세고 Swift는 grapheme으로 세므로
    /// 두 언어가 "글자 수"에 합의할 수 없다. 클라가 30 grapheme으로 자르고 서버는 컬럼 상한만 지킨다.
    static let maxLength = 30

    /// 첫 곡·첫 아티스트는 번호 배지 ①(position 0) 기준.
    /// `distinctArtistCount`는 artist_name 문자열 기준이라 `feat.` 표기가 다르면 2명으로 잡힌다 —
    /// 정규화하면 `feat.`/`&`/`with` 파싱이 끝없어서 그대로 둔다.
    static func fallback(firstTrack: String,
                         firstArtist: String,
                         trackCount: Int,
                         distinctArtistCount: Int) -> String {
        if distinctArtistCount > 1 {
            return String(localized: "\(firstArtist) and \(distinctArtistCount - 1) others",
                          comment: "픽 폴백 제목 — 아티스트 여러 명")
        }
        if trackCount > 1 {
            return String(localized: "\(firstTrack) by \(firstArtist) and \(trackCount - 1) more",
                          comment: "픽 폴백 제목 — 아티스트 1명, 여러 곡")
        }
        return String(localized: "\(firstTrack) by \(firstArtist)",
                      comment: "픽 폴백 제목 — 1곡")
    }

    static func fallback(for pick: API.Pick) -> String {
        fallback(firstTrack: pick.firstTrackName,
                 firstArtist: pick.firstArtistName,
                 trackCount: pick.trackCount,
                 distinctArtistCount: pick.distinctArtistCount)
    }

    /// 서버에 넘길 제목. 공백만 남으면 nil — 빈 문자열과 null이 둘 다 "제목 없음"이면
    /// 폴백 판정이 두 갈래로 갈린다.
    static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 제목만 바꾼다(`13_mypage_ia_after_picks.md` §3). 낙관적으로 목록부터 고치고,
    /// 실패하면 되돌린 뒤 이유를 `onFailure`로 넘긴다 — 조용히 되돌리면 유저는 저장된 줄 알고
    /// 나갔다가 옛 제목을 다시 본다. 금칙어(400 `PICK_TITLE_BLOCKED`)는 서버가 로케일에 맞춘
    /// 문구를 내려주므로 그대로 쓴다.
    ///
    /// **픽 탭과 프로필의 내 픽 목록이 이 함수를 같이 쓴다.** 진입점이 둘이 되면서 낙관적
    /// 갱신과 롤백을 두 벌 관리하지 않으려고 여기 한 벌만 둔다.
    @MainActor
    static func rename(_ pick: API.Pick, to title: String?,
                       in picks: Binding<[API.Pick]>,
                       api: APIClient,
                       onFailure: @escaping (String) -> Void) {
        guard let index = picks.wrappedValue.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
        let previous = picks.wrappedValue[index].title
        guard previous != title else { return }
        picks.wrappedValue[index].title = title

        Task {
            do { try await api.send(.updatePickTitle(id: pick.pickId, title: title)) }
            catch {
                guard let i = picks.wrappedValue.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
                picks.wrappedValue[i].title = previous
                // `error`는 `any Error`라 enum 케이스 패턴이 바로 안 붙는다 — 먼저 캐스팅한다.
                if let apiError = error as? APIError, case .server(_, let message, _) = apiError {
                    onFailure(message)
                } else {
                    onFailure(String(localized: "Couldn't save. Try again."))
                }
            }
        }
    }
}

/// 픽 반응 이모지. 시딩 단계엔 **한 종류만** 쓴다 — 5종을 깔면 얼마 안 되는 반응이
/// 잘게 쪼개져 카드마다 0이 도배되고, 그게 "아무도 안 쓰는 앱"으로 읽힌다.
/// 서버 화이트리스트는 5종 그대로 두므로 늘릴 땐 클라만 고치면 된다.
enum PickReaction {
    /// 서버로 보내는 값이자 화면에 그리는 글리프. 카드에선 알약(버블) 안에 들어간다 —
    /// 배경 없는 아이콘 행에 혼자 놓으면 tint가 안 먹는 이모지가 겉돈다.
    static let primary = "🔥"

    /// VoiceOver 라벨. 이모지만 두면 스크린리더가 유니코드 이름을 읽는다.
    static let label: LocalizedStringKey = "Fire"
}
