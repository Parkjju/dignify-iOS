import SwiftUI

/// 하입 목록과 검색 결과가 같은 목록에 섞이므로 두 wire 타입을 하나로 접는다.
struct PickTrack: Identifiable, Equatable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let artworkUrl: String
    let previewUrl: String
    /// 하입한 시각. 검색 결과에는 없다 — 날짜 구분 없이 한 덩어리로 깔린다.
    let hypedAt: Date?

    var id: Int { trackId }

    /// **trackId만 본다.** 같은 곡이 검색 결과에는 `hypedAt` 없이, 하입 목록에는 있는 채로 온다 —
    /// 필드를 전부 비교하면 검색에서 고른 곡이 목록으로 돌아왔을 때 미선택으로 보이고 두 번 담긴다.
    static func == (lhs: PickTrack, rhs: PickTrack) -> Bool { lhs.trackId == rhs.trackId }

    init(_ item: API.HypeItem) {
        self.init(trackId: item.trackId, trackName: item.trackName,
                  artistName: item.artistName, artworkUrl: item.artworkUrl,
                  previewUrl: item.previewUrl, hypedAt: item.hypedAt)
    }

    init(_ item: API.FeedItem) {
        self.init(trackId: item.trackId, trackName: item.trackName,
                  artistName: item.artistName, artworkUrl: item.artworkUrl,
                  previewUrl: item.previewUrl)
    }

    init(trackId: Int, trackName: String, artistName: String, artworkUrl: String,
         previewUrl: String = "", hypedAt: Date? = nil) {
        self.trackId = trackId
        self.trackName = trackName
        self.artistName = artistName
        self.artworkUrl = artworkUrl
        self.previewUrl = previewUrl
        self.hypedAt = hypedAt
    }
}

/// 재생 가능한 선택 셀. **행 본문 탭 = 프리뷰 재생이고, 선택은 오른쪽 별도 표적이다.**
/// 소리를 들어보고 고르게 하려는 것이라 두 동작을 한 탭에 겹치면 안 된다 —
/// 겹치면 아는 이름만 보고 고르게 되고, 그게 2지선다 온보딩을 만든 이유였다.
///
/// 픽 만들기와 온보딩 시드 고르기가 같이 쓴다. **공유하는 건 이 셀까지고 레이아웃은 아니다** —
/// 하입 목록은 이미 만난 곡을 회상하는 지면(리스트+날짜), 온보딩은 모르는 곡을 훑는 지면(그리드)이다.
struct PickTrackRow: View {
    let track: PickTrack
    /// 선택 순번(1부터). nil이면 미선택. 순번이 곧 재생 순서라 체크가 아니라 숫자다.
    let number: Int?
    let isPlaying: Bool
    let onPlay: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            selectButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(track.trackName), \(track.artistName)"))
        .accessibilityAddTraits(number != nil ? .isSelected : [])
    }

    /// 재생 표시를 **재생 중일 때만** 띄우면 여기가 눌러서 들어보는 자리라는 걸 아무도 모른다.
    /// 그래서 정지 상태에도 흐린 삼각형을 남기고, 재생 중에만 스크림을 진하게 한다.
    private var artwork: some View {
        AsyncImage(url: track.artworkUrl.itunesArtworkURL(size: 200)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            DSColor.surface
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            ZStack {
                Color.black.opacity(isPlaying ? 0.45 : 0.22)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(isPlaying ? 1 : 0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .animation(.easeOut(duration: 0.12), value: isPlaying)
    }

    /// 배지는 24pt인데 **표적은 44pt**다 — 그리드에서 20pt 배지를 그대로 표적으로 썼다가
    /// 자꾸 빗나갔다(`HypeCollection`의 제거 배지와 같은 판정).
    private var selectButton: some View {
        Button(action: onToggle) {
            Group {
                if let number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(DSColor.brand, in: Circle())
                        .transition(.scale)
                } else {
                    Circle()
                        .strokeBorder(DSColor.textTertiary, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: number)
        .accessibilityLabel(number == nil ? Text("Select") : Text("Deselect"))
    }
}

#if DEBUG
#Preview("Row") {
    VStack(spacing: 0) {
        PickTrackRow(track: PickPreview.tracks[0], number: nil, isPlaying: false,
                     onPlay: {}, onToggle: {})
        PickTrackRow(track: PickPreview.tracks[1], number: 2, isPlaying: true,
                     onPlay: {}, onToggle: {})
    }
    .padding(.horizontal, 20)
}
#endif
