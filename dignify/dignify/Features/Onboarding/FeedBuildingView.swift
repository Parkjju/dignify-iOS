import SwiftUI

/// 피드 구성 중 — 추천 기준 곡을 고른 직후 첫 피드를 받는 동안. 고른 곡이 피드를 만든다는 걸 보여 준다.
/// 명세: dignify-design `components/feed-building/feed-building.md`. 노출 시간(최소 1초)은 부르는 쪽이 정한다.
struct FeedBuildingView: View {
    /// 고른 곡 커버. 앞에서 최대 3장.
    let covers: [URL?]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            VStack(spacing: 0) {
                coverStack(t)
                    .padding(.bottom, 32)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Building a feed that fits your taste")
                    dots(t)
                }
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
                Text("Looking for tracks that sound like your picks")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
    }

    /// 96 커버를 −20씩 겹쳐 −8°/0/8°로 펼친다. 1.6초 주기로 0.2초씩 차례로 8만큼 둥실.
    private func coverStack(_ t: TimeInterval) -> some View {
        let shown = Array(covers.prefix(3))
        // 한 장이면 똑바로, 둘이면 0°/8°, 셋이면 −8°/0/8°.
        let tilt = shown.count == 3 ? 1 : 0
        return HStack(spacing: -20) {
            ForEach(shown.indices, id: \.self) { i in
                cover(shown[i])
                    .rotationEffect(.degrees(Double(i - tilt) * 8))
                    .offset(y: -8 * float(t - Double(i) * 0.2))
                    .zIndex(i == 1 ? 1 : 0)
            }
        }
    }

    private func cover(_ url: URL?) -> some View {
        RemoteImage(url: url) { DSColor.surface }
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 8)
    }

    /// 0 → 1 → 0, ease-in-out.
    private func float(_ t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        return (1 - cos(t.truncatingRemainder(dividingBy: 1.6) / 1.6 * 2 * .pi)) / 2
    }

    /// 말줄임 점이 0.2초 간격으로 차례로 밝아진다(1.2초 주기).
    private func dots(_ t: TimeInterval) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Text(verbatim: ".").opacity(dotLit(i, t) ? 1 : 0.2)
            }
        }
    }

    private func dotLit(_ i: Int, _ t: TimeInterval) -> Bool {
        let delay = Double(i) * 0.2
        guard !reduceMotion else { return true }
        guard t >= delay else { return false }
        return (t - delay).truncatingRemainder(dividingBy: 1.2) / 1.2 > 0.2
    }
}

#Preview {
    FeedBuildingView(covers: [nil, nil, nil])
}
