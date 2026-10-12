import SwiftUI

/// 피드 제스처 코치마크 — 손 모션을 보고 **따라 해야** 다음 단계로 넘어간다. 「다음」 버튼이 없다.
/// 명세: dignify-design `components/coach-gesture/coach-gesture.md` (feed_coachmark 1.0·1.1).
///
/// 읽고 넘기는 스포트라이트(`CoachMarkOverlay`)와 달리 화면을 어둡게 덮지 않는다 — 아트워크 자체가 대상이라서.
/// 아트워크 `overlay`에 붙으므로 좌표를 적지 않는다. 카드를 끌면 같이 끌려간다.
enum FeedCoachStep {
    case doubleTap, hyped, swipeUp
}

/// 1.1 확정값. 시안 「코치마크 — 직접 해 보기」의 Controls와 이름을 맞췄다.
enum FeedCoachMotion {
    static let speed: Double = 1
    // hold(큰 하트가 머무는 시간)는 피드 좋아요 모션(`FeedView.LikeMotion`)이 갖는다 — 큰 하트를 그쪽이 그린다.
    /// 손 중심이 아트워크 가운데에서 얼마나 위로.
    static let handOffset: CGFloat = -18
    /// 캡션 아래 끝이 아트워크 밑으로 삐져나오는 길이.
    static let captionBelow: CGFloat = 25
    /// 스와이프 단계에서 화면이 따라 올라가는 높이.
    static let peek: CGFloat = 32

    /// 탭 두 번(1초 안) + 쉼 1초.
    static let doubleTapCycle = 2.0 / speed
    /// 쓸어 올림 1.2초 + 쉼. 화면 힌트도 같은 주기다.
    static let swipeCycle = 2.4 / speed

    /// 스와이프 단계의 화면 힌트(음수 = 위로). **손과 같은 시작 시각으로 계산해야** 박자가 맞는다.
    /// 0.3초부터 올라가 1.15초에 −32, 1.7초까지 살짝 튕기며 제자리.
    static func peekOffset(at elapsed: TimeInterval) -> CGFloat {
        let p = phase(elapsed, cycle: swipeCycle)
        switch p {
        case ..<0.12: return 0
        case ..<0.48: return -peek * easeInOut((p - 0.12) / 0.36)
        case ..<0.72: return -peek * (1 - easeOutBack((p - 0.48) / 0.24))
        default: return 0
        }
    }

    static func phase(_ elapsed: TimeInterval, cycle: Double) -> Double {
        max(0, elapsed).truncatingRemainder(dividingBy: cycle) / cycle
    }

    /// 꺾은선 보간. 시안 CSS keyframes의 (진행률, 값)을 그대로 옮겨 쓴다.
    static func interpolate(_ p: Double, _ stops: [(Double, Double)]) -> Double {
        guard let first = stops.first else { return 0 }
        if p <= first.0 { return first.1 }
        for (a, b) in zip(stops, stops.dropFirst()) where p <= b.0 {
            let t = b.0 == a.0 ? 1 : (p - a.0) / (b.0 - a.0)
            return a.1 + (b.1 - a.1) * t
        }
        return stops.last!.1
    }

    static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.2, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

/// 아트워크 위에 얹는 손 + 캡션. 탭은 통과시킨다 — 제스처는 피드 페이징 레이어 한 곳에만 산다.
struct FeedCoachOverlay: View {
    let step: FeedCoachStep
    /// 스와이프 단계 주기의 시작 시각. 피드가 화면 힌트를 같은 값으로 돌린다.
    /// nil = 멈춤(유저가 잡고 끄는 중). 더블탭 단계는 혼자 돌아서 안 쓴다.
    let cycleStart: Date?

    var body: some View {
        ZStack {
            mark
                .offset(y: FeedCoachMotion.handOffset)
            caption
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: FeedCoachMotion.captionBelow)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mark: some View {
        switch step {
        case .doubleTap: CoachHand(gesture: .doubleTap, cycleStart: nil, paused: false)
        case .swipeUp: CoachHand(gesture: .swipeUp, cycleStart: cycleStart, paused: cycleStart == nil)
        case .hyped: EmptyView()   // 큰 하트는 피드 좋아요 모션이 그린다(1.2). 여기선 캡션만.
        }
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(DSTypography.headline)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(DSColor.pickElevated, in: RoundedRectangle(cornerRadius: DSRadius.medium))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .doubleTap: "Found a track you like!"
        case .hyped: "You liked this track!"
        case .swipeUp: "Ready for the next track?"
        }
    }

    private var message: LocalizedStringKey {
        switch step {
        case .doubleTap: "Try tapping twice, quickly."
        case .hyped: "Want to go find more tracks that catch your ear?"
        case .swipeUp: "Swipe up on the screen."
        }
    }
}

/// 손 72 + 누름 물결. 손끝이 기준점에 오도록 시안처럼 오른쪽 아래로 살짝 민다.
private struct CoachHand: View {
    let gesture: FeedCoachStep
    /// nil이면 이 뷰가 나타난 시각부터 돈다.
    let cycleStart: Date?
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()

    var body: some View {
        // 동작 줄이기·잡는 중이면 멈춘 채 보인다(물결·이동 없음).
        let still = paused || reduceMotion
        TimelineView(.animation(paused: still)) { context in
            let elapsed = context.date.timeIntervalSince(cycleStart ?? appearedAt)
            hand(still ? nil : elapsed)
        }
        .offset(x: 6, y: 22)
    }

    private func hand(_ elapsed: TimeInterval?) -> some View {
        let pose = elapsed.map(pose(at:)) ?? Pose()
        return ZStack(alignment: .topLeading) {
            Image("HandTap")
                .resizable()
                .frame(width: 72, height: 72)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
                .scaleEffect(pose.scale, anchor: UnitPoint(x: 0.3, y: 0.1))
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 28, height: 28)
                .scaleEffect(pose.ringScale)
                .opacity(pose.ringOpacity)
                .position(x: 14, y: 2)
        }
        .frame(width: 72, height: 72)
        .offset(y: pose.y)
        .opacity(pose.opacity)
    }

    private struct Pose {
        var scale = 1.0, ringScale = 1.0, ringOpacity = 0.0, y: CGFloat = 0, opacity = 1.0
    }

    /// 시안 `coach-gesture.css`의 keyframes(`dsg-tap`·`dsg-ring`·`dsg-swipe`)를 진행률로 옮겼다.
    private func pose(at elapsed: TimeInterval) -> Pose {
        let m = FeedCoachMotion.self
        switch gesture {
        case .swipeUp:
            let p = m.phase(elapsed, cycle: m.swipeCycle)
            let rise = m.easeInOut(min(1, p / 0.5))
            return Pose(y: 70 - 140 * rise,
                        opacity: m.interpolate(p, [(0, 0), (0.12, 1), (0.5, 1), (0.6, 0), (1, 0)]))
        default:
            let p = m.phase(elapsed, cycle: m.doubleTapCycle)
            return Pose(
                scale: m.interpolate(p, [(0, 1), (0.075, 0.86), (0.15, 1), (0.24, 0.86), (0.315, 1), (1, 1)]),
                ringScale: m.interpolate(p, [(0, 0.4), (0.165, 1.6), (0.18, 0.4), (0.345, 1.6), (1, 1.6)]),
                ringOpacity: m.interpolate(p, [(0, 0), (0.075, 1), (0.165, 0), (0.18, 0), (0.24, 1), (0.345, 0), (1, 0)])
            )
        }
    }
}
