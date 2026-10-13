import SwiftUI

/// 고른 곡 트레이(feed_coachmark 1.3, 디자인 `components/seed-tray`). 온보딩 곡 고르기와
/// 마이 「추천 기준 곡」이 같이 쓴다. 그리드를 스크롤해 고른 곡이 화면 밖으로 나가도 무엇을 골랐는지
/// 늘 보이고, 여기서 바로 빼거나 그 곡으로 간다.
///
/// **비어 있어도 숨기지 않는다** — 빈 칸 세 개가 "3곡까지"를 말한다.
struct SeedTray: View {
    struct Slot: Identifiable {
        let id: Int            // trackId
        let artworkUrl: String
    }

    let slots: [Slot]
    let limit: Int
    /// 온보딩은 고른 순서가 타일 번호라 같은 번호를 단다. 마이는 체크 표시라 순서가 없다.
    var numbered = true
    let onTap: (Int) -> Void
    let onRemove: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Selected tracks")
                    Text(verbatim: "\(slots.count)/\(limit)").foregroundStyle(DSColor.brand)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                Text(slots.count >= limit ? "Remove one to swap" : "Tap to jump to it")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(0..<limit, id: \.self) { index in
                    if index < slots.count {
                        filled(slots[index], number: index + 1)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DSColor.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 52, height: 52)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: slots.map(\.id))
    }

    private func filled(_ slot: Slot, number: Int) -> some View {
        RemoteImage(url: slot.artworkUrl.itunesArtworkURL(size: 160)) { DSColor.surface }
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onTap(slot.id) }
            .overlay(alignment: .bottomLeading) {
                if numbered {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(DSColor.brand, in: Circle())
                        .overlay { Circle().strokeBorder(DSColor.background, lineWidth: 2).padding(-2) }
                        .offset(x: -4, y: 4)
                        .allowsHitTesting(false)
                }
            }
            // 보이는 원은 20인데 표적은 44다. 52 칸 위에 44를 얹으면 커버 탭과 겹치므로 바깥으로 반쯤 뺀다.
            .overlay(alignment: .topTrailing) {
                Button { onRemove(slot.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(DSColor.textPrimary, in: Circle())
                        .overlay { Circle().strokeBorder(DSColor.background, lineWidth: 2).padding(-2) }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 6 + 12, y: -6 - 12)
                .accessibilityLabel(Text("Deselect"))
            }
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}
