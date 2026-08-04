#if DEBUG
import Foundation

/// 프리뷰 전용 목업. 백엔드에 `picks`가 아직 없어서 화면을 눈으로 확인할 방법이 이것뿐이다.
/// 아트워크는 실제 카탈로그 URL이라 스택 썸네일이 진짜 크기·비율로 보인다.
/// ponytail: 릴리스 빌드엔 안 실린다. 서버가 나오면 통째로 지운다.
enum PickPreview {
    static let artwork = [
        "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/b3/27/1f/b3271f8d-0091-aacf-e1df-a8e1b4b7981b/859735924583_cover.jpg/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/01/2d/09/012d0947-6e77-3737-0f13-53345267a1de/4065142020404.jpg/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/51/ed/28/51ed2854-6729-c016-f977-886638bcf400/089795938224.png/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/10/b0/67/10b0673f-6619-4da6-2119-0279d433e280/118139.jpg/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/11/16/c3/1116c3d5-175d-de51-dea5-53f3f1e300f3/741869412237.jpg/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/1b/c6/1e/1bc61e07-1152-1823-f41d-f8c0583362f0/859785836331_cover.jpg/100x100bb.jpg",
    ]

    /// 카드가 갈리는 축을 전부 한 화면에 깐다: 제목 유무·폴백 3분기·곡 수(1/3/4+)·반응 0/있음·내 픽.
    static let picks: [API.Pick] = [
        // 제목 있음 + 반응 여러 개 + 내가 누른 것 + 4곡 이상(+N 배지)
        API.Pick(pickId: 1, title: "새벽 세 시에 듣는 것들", nickname: "parkjju", isMine: false,
                 createdAt: .now.addingTimeInterval(-3600 * 3),
                 trackCount: 7, distinctArtistCount: 5,
                 firstArtistName: "Margaret Cho", firstTrackName: "Yer Dihh",
                 thumbnails: Array(artwork.prefix(3)),
                 reactions: ["🔥": 12, "🫶": 5, "👀": 1], myReaction: "🔥"),
        // 제목 없음 + 아티스트 여러 명 폴백 + 반응 0 (행 높이 고정 확인)
        API.Pick(pickId: 2, title: nil, nickname: "digger_kim", isMine: false,
                 createdAt: .now.addingTimeInterval(-3600 * 26),
                 trackCount: 4, distinctArtistCount: 4,
                 firstArtistName: "The Fixx", firstTrackName: "Stand or Fall",
                 thumbnails: Array(artwork.dropFirst(1).prefix(3)),
                 reactions: [:], myReaction: nil),
        // 제목 없음 + 아티스트 1명·N곡 폴백 + 3곡(오프셋 스택, +N 없음)
        API.Pick(pickId: 3, title: nil, nickname: "nightowl", isMine: false,
                 createdAt: .now.addingTimeInterval(-60 * 40),
                 trackCount: 3, distinctArtistCount: 1,
                 firstArtistName: "Joey DeFrancesco", firstTrackName: "In Times of Reflection",
                 thumbnails: Array(artwork.dropFirst(3).prefix(3)),
                 reactions: ["🪩": 3], myReaction: nil),
        // 2곡 — 스택이 두 장만 겹치는 경우
        API.Pick(pickId: 5, title: "둘이서 듣기 좋은", nickname: "sunset_kim", isMine: false,
                 createdAt: .now.addingTimeInterval(-3600 * 7),
                 trackCount: 2, distinctArtistCount: 2,
                 firstArtistName: "Evan Johnson", firstTrackName: "Without You",
                 thumbnails: Array(artwork.dropFirst(2).prefix(2)),
                 reactions: ["🫶": 8, "🥲": 2], myReaction: nil),
        // 내 픽(메뉴가 삭제로 갈림) + 1곡(스택 아닌 한 장) + 아주 긴 제목(2줄 말줄임)
        API.Pick(pickId: 4, title: "여름 끝자락에 계속 돌려 듣게 되는 곡 하나", nickname: "me", isMine: true,
                 createdAt: .now.addingTimeInterval(-60 * 5),
                 trackCount: 1, distinctArtistCount: 1,
                 firstArtistName: "Privaledge", firstTrackName: "Savage",
                 thumbnails: [artwork[5]],
                 reactions: ["🥲": 2], myReaction: "🥲"),
    ]

    /// 한계값만 모은 세트. 닉네임은 서버 정규식 상한(`^[a-zA-Z0-9_가-힣]{1,20}$`)인 20자,
    /// 곡 수는 픽 상한인 30곡, 제목은 입력 상한인 30 grapheme, 시간은 상대표기가 가장 길어지는 구간.
    /// 한글 20자가 라틴 20자보다 훨씬 넓어서 ko가 더 가혹한 케이스다.
    static let edgeCases: [API.Pick] = [
        // 한글 닉네임 20자 + 30곡 + 제목 30자(2줄 꽉)
        API.Pick(pickId: 101, title: "새벽 세 시에 혼자 듣고 싶어지는 노래들만 골라 담았어",
                 nickname: "디깅하는사람이십년째그냥계속듣는중입니다",
                 isMine: false, createdAt: .now.addingTimeInterval(-3600 * 24 * 340),
                 trackCount: 30, distinctArtistCount: 24,
                 firstArtistName: "Margaret Cho", firstTrackName: "Yer Dihh",
                 thumbnails: Array(artwork.prefix(3)),
                 reactions: ["🔥": 128, "🫶": 64, "🥲": 32, "🪩": 16, "👀": 8], myReaction: "🪩"),
        // 라틴 닉네임 20자(_ 포함) + 30곡 + 폴백 제목(아티스트명이 긴 경우)
        API.Pick(pickId: 102, title: nil,
                 nickname: "digging_all_night_00",
                 isMine: false, createdAt: .now.addingTimeInterval(-60 * 11),
                 trackCount: 30, distinctArtistCount: 1,
                 firstArtistName: "Teddy Wilson, Teddy Wilson Jr & Lionel Hampton",
                 firstTrackName: "Limehouse Blues (Slowed + Reverb)",
                 thumbnails: Array(artwork.dropFirst(2).prefix(3)),
                 reactions: [:], myReaction: nil),
        // 반대 극단 — 최소값. 1곡·짧은 닉네임·짧은 제목
        API.Pick(pickId: 103, title: "여름", nickname: "kj",
                 isMine: true, createdAt: .now,
                 trackCount: 1, distinctArtistCount: 1,
                 firstArtistName: "Privaledge", firstTrackName: "Savage",
                 thumbnails: [artwork[5]],
                 reactions: ["👀": 1], myReaction: nil),
    ]

    /// 만들기 화면 그리드용(크레이트 목업).
    static let tracks: [PickTrack] = [
        PickTrack(trackId: 30435, trackName: "Yer Dihh (feat. Jane Wiedlin)", artistName: "Margaret Cho", artworkUrl: artwork[0]),
        PickTrack(trackId: 71256, trackName: "Stand or Fall (Rerecorded)", artistName: "The Fixx", artworkUrl: artwork[1]),
        PickTrack(trackId: 47106, trackName: "Without You", artistName: "Evan Johnson", artworkUrl: artwork[2]),
        PickTrack(trackId: 16973, trackName: "In Times of Reflection", artistName: "Joey DeFrancesco", artworkUrl: artwork[3]),
        PickTrack(trackId: 16094, trackName: "Limehouse Blues", artistName: "Teddy Wilson", artworkUrl: artwork[4]),
        PickTrack(trackId: 66948, trackName: "Savage (feat. C. King)", artistName: "Privaledge", artworkUrl: artwork[5]),
    ]
}
#endif
