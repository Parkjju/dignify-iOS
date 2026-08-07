import SwiftUI
import UIKit

/// 픽을 SNS에 올릴 9:16 이미지 카드. `ShareCardView`(트랙 1곡짜리)와 같은 골격이고,
/// **곡 목록이 들어간다**는 점만 다르다 — 커버만 있는 그림은 플레이리스트로 안 읽힌다.
///
/// 링크가 아니라 이미지인 이유: 픽을 열어줄 웹 페이지가 아직 없다(`dignify-web`은 랜딩 한 장).
/// 페이지가 생기면 이 카드에 URL을 얹어 같이 내보내면 된다.
///
/// 아트워크는 `ImageRenderer`가 비동기 로딩을 못 기다리므로 **렌더 전에 `UIImage`로 확보해
/// 주입한다.** `AsyncImage`를 그대로 두면 빈 칸으로 찍힌다.
struct PickShareCardView: View {
    let cover: UIImage?
    let title: String
    let nickname: String
    let trackCount: Int
    /// 표시할 곡 (최대 `maxRows`). 상세 요청이 실패하면 빈 배열이고, 그때도 카드는 성립한다.
    let tracks: [(name: String, artist: String)]

    static let size = CGSize(width: 360, height: 640)
    private static let maxRows = 5

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Text(verbatim: "PICK")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 44)
                Spacer()
                coverArt
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 22)
                Text(verbatim: "@\(nickname)")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.top, 6)
                trackList
                    .padding(.top, 20)
                Spacer()
                ShareCardFooter()
                    .padding(.bottom, 40)
            }
            // padding이 아니라 고정 frame. ImageRenderer는 폭 제안 없이 렌더할 수 있어서
            // padding만 있으면 Text가 줄바꿈 없이 카드 밖으로 잘린다(1.0.7에서 밟은 버그).
            .frame(width: Self.size.width - 64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private var background: some View {
        if let cover {
            Image(uiImage: cover)
                .resizable()
                .scaledToFill()
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.55))
        } else {
            LinearGradient(colors: [DSColor.brand, Color(hex: 0x2A2350)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private var coverArt: some View {
        Group {
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                DSColor.brandLight
            }
        }
        .frame(width: 180, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    /// 번호 = 재생 순서. 남는 곡은 마지막 줄에 수로만 접는다 —
    /// 다 적으면 9:16 안에서 글자가 작아져 아무것도 안 읽힌다.
    private var trackList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(tracks.prefix(Self.maxRows).enumerated()), id: \.offset) { index, track in
                HStack(spacing: 8) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 12, alignment: .trailing)
                    Text(track.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if trackCount > tracks.prefix(Self.maxRows).count {
                // 숫자를 String으로 넘겨 키를 `+%@ more`로 고정한다 — 정수 보간(`%lld`)은
                // 문자열 카탈로그 심볼 생성에서 이미 한 번 빌드를 깼다.
                Text("+\(String(trackCount - tracks.prefix(Self.maxRows).count)) more")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PickShareCard {
    /// 커버를 `UIImage`로 확보한 뒤 카드를 렌더한다. 곡 목록은 `GET /picks/{id}`가 준
    /// `FeedItem`을 그대로 받는다 — 별도 매핑 타입을 만들 이유가 없다.
    @MainActor
    static func render(pick: API.Pick, tracks: [API.FeedItem]) async -> UIImage? {
        let cover = await ShareCard.loadImage(pick.thumbnails.first.flatMap { $0.itunesArtworkURL(size: 600) })
        let renderer = ImageRenderer(
            content: PickShareCardView(
                cover: cover,
                title: pick.title ?? PickTitle.fallback(for: pick),
                nickname: pick.nickname,
                trackCount: pick.trackCount,
                tracks: tracks.map { (name: $0.trackName, artist: $0.artistName) }
            )
        )
        renderer.scale = 3   // 360×640 → 1080×1920
        return renderer.uiImage
    }
}

#if DEBUG
#Preview {
    PickShareCardView(
        cover: nil,
        title: "새벽 세 시에 듣는 것들",
        nickname: "parkjju",
        trackCount: 7,
        tracks: [("Ivy", "Frank Ocean"), ("Stand or Fall", "The Fixx"),
                 ("Without You", "Evan Johnson"), ("Savage", "Privaledge"),
                 ("In Times of Reflection", "Joey DeFrancesco")]
    )
}
#endif
