import SwiftUI
import PostHog

/// 코치마크 — 실제 UI 요소를 뚫어 보여주는 1회성 안내. 카드 캐러셀(`TutorialView`)과 달리
/// **가리키는 대상이 화면에 실재한다**는 게 값이다. 픽 탭 첫 진입에서만 돈다.
///
/// **좌표를 한 줄도 안 적는다.** 대상 뷰가 `anchorPreference`로 자기 `bounds`를 올려 보내고,
/// 오버레이가 `GeometryProxy[anchor]`로 자기 좌표계에서 다시 읽는다 — 레이아웃이 끝난 뒤의
/// 실측값이라 SE든 Pro Max든 Dynamic Type이 커져 있든 구멍이 요소 위에 정확히 앉는다.
/// 카드 위치도 측정한 사각형에서 파생시킨다(아래쪽 요소면 카드가 위로 간다).

// MARK: - 앵커 수집

/// 코치마크가 가리킬 수 있는 자리. 케이스를 늘리려면 대상 뷰에 `.coachAnchor(_:)`만 붙이면 된다.
enum CoachAnchor: String, CaseIterable {
    case play, react, share, compose
}

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachAnchor: Anchor<CGRect>] = [:]

    /// 같은 키가 여러 번 오면 **나중 것을 쓴다.** 목록에 카드가 여러 장이어도 앵커를 다는 건
    /// 첫 카드뿐이라 실제로는 충돌하지 않지만, 규칙은 정해둬야 조용히 엉뚱한 카드를 가리키지 않는다.
    static func reduce(value: inout [CoachAnchor: Anchor<CGRect>],
                       nextValue: () -> [CoachAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 이 뷰의 위치·크기를 코치마크에 알린다. 붙여도 레이아웃은 안 바뀐다.
    /// nil이면 아무것도 안 올린다 — 첫 카드만 앵커를 다는 분기를 호출부에서 삼항으로 쓰기 위해서다.
    func coachAnchor(_ id: CoachAnchor?) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { anchor in
            id.map { [$0: anchor] } ?? [:]
        }
    }

    /// 구멍 뚫기. `destinationOut`은 합성 그룹 안에서만 먹으므로 `compositingGroup()`이 필수다.
    fileprivate func punchOut<S: View>(@ViewBuilder _ shape: () -> S) -> some View {
        mask {
            Rectangle()
                .overlay { shape().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}

// MARK: - 스텝

struct CoachStep {
    let anchor: CoachAnchor
    let title: LocalizedStringKey
    let body: LocalizedStringKey
    /// 원형으로 뚫을지. 커버처럼 큰 사각 요소는 사각형이 자연스럽고, 버튼은 원/알약이 낫다.
    let circular: Bool
}

enum PicksCoach {
    /// 순서 = 픽을 쓰는 순서다. 보는 것(재생) → 반응 → 공유 → 만들기.
    static let steps: [CoachStep] = [
        CoachStep(anchor: .play,
                  title: "Tap to play",
                  body: "Tap the cover and the tracks in this pick play one after another.",
                  circular: false),
        CoachStep(anchor: .react,
                  title: "React with 🔥",
                  body: "Liked it? Tap 🔥 — the person who made it sees the count.",
                  circular: true),
        CoachStep(anchor: .share,
                  title: "Share as a card",
                  body: "Turn a pick into an image card and post it to Instagram or anywhere else.",
                  circular: true),
        CoachStep(anchor: .compose,
                  title: "Make your own",
                  body: "Put the tracks you've kept together and send out your own pick.",
                  circular: true),
    ]
}

// MARK: - 오버레이

struct CoachMarkOverlay: View {
    let steps: [CoachStep]
    let anchors: [CoachAnchor: Anchor<CGRect>]
    let proxy: GeometryProxy
    let onFinish: () -> Void

    @State private var index = 0

    private var step: CoachStep { steps[index] }

    /// 이번 스텝이 가리키는 사각형. 대상이 화면 밖으로 밀려 앵커가 없으면 nil —
    /// 그때는 구멍 없이 설명 카드만 띄운다(진행이 막히는 것보다 낫다).
    private var spot: CGRect? {
        guard let anchor = anchors[step.anchor] else { return nil }
        return proxy[anchor].insetBy(dx: -8, dy: -8)
    }

    var body: some View {
        ZStack {
            dimmed
            infoCard
        }
        // **`ignoresSafeArea`를 여기 붙이면 안 된다.** 구멍과 카드는 `proxy` 좌표계로 계산하는데,
        // 이 뷰만 세이프에어리어 밖으로 넓히면 원점이 화면 맨 위로 올라가 상단 인셋(약 47pt)만큼
        // 전부 위로 밀린다 — 그 어긋남이 카드가 가리킬 자리를 덮어버린 원인이었다.
        // 확장은 호출부에서 `GeometryReader` 자체에 걸어 **좌표계까지 같이** 넓힌다.
        //
        // 뒤쪽 UI가 눌리면 안 된다. 안내 중에 재생이 시작되면 설명이 무슨 말인지 알 수 없다.
        .contentShape(Rectangle())
        .onTapGesture { }
        .transition(.opacity)
    }

    private var dimmed: some View {
        Color.black.opacity(0.72)
            .punchOut {
                if let spot {
                    Group {
                        if step.circular {
                            Circle().frame(width: max(spot.width, spot.height),
                                           height: max(spot.width, spot.height))
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .frame(width: spot.width, height: spot.height)
                        }
                    }
                    .position(x: spot.midX, y: spot.midY)
                }
            }
            // 구멍 테두리. 어두운 지면에서 뚫린 자리가 그냥 밝은 얼룩으로 안 읽히게 한다.
            .overlay {
                if let spot {
                    Group {
                        if step.circular {
                            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
                                .frame(width: max(spot.width, spot.height),
                                       height: max(spot.width, spot.height))
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                                .frame(width: spot.width, height: spot.height)
                        }
                    }
                    .position(x: spot.midX, y: spot.midY)
                }
            }
    }

    /// 카드는 **구멍 반대쪽**, 그중에서도 **남는 자리가 더 넓은 쪽**에 붙는다.
    ///
    /// 이전엔 "대상이 화면 위쪽이면 아래"로만 갈랐고 여백을 화면의 55%로 잘랐는데,
    /// 그 상한이 카드를 구멍 위로 도로 끌어와 가리킬 자리를 덮었다. 상한을 없애고
    /// **여백을 실측 사각형에서만** 계산하면 카드가 구멍 경계를 넘을 수가 없다.
    private var infoCard: some View {
        let height = proxy.size.height
        let spot = spot ?? CGRect(x: 0, y: height / 2, width: 0, height: 0)
        // 위아래 중 넓은 쪽. 같으면 아래(읽는 방향이라 아래가 자연스럽다).
        let below = (height - spot.maxY) >= spot.minY

        return card
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: below ? .top : .bottom)
            // 구멍에서 24pt 떨어뜨린다. 반대쪽 여백은 0이라 카드가 남는 자리를 다 쓴다.
            .padding(.top, below ? spot.maxY + 24 : 0)
            .padding(.bottom, below ? 0 : height - spot.minY + 24)
            // 상태바·홈 인디케이터에 카드가 닿지 않게 하는 최소 여백.
            .padding(.vertical, 16)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(step.body)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            dots.padding(.top, 20)
            Button(action: advance) {
                Text(index == steps.count - 1 ? "Get started" : "Next")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DSColor.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(24)
        // 폭은 화면에서 파생시키되 상한을 둔다 — 큰 화면에서 한 줄이 지나치게 길어지면 안 읽힌다.
        .frame(maxWidth: 420)
        .background(DSColor.pickElevated, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// 현재 스텝만 길쭉한 알약. 개수는 스텝 수에서 나온다.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? .white : .white.opacity(0.25))
                    .frame(width: i == index ? 20 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }

    private func advance() {
        if index == steps.count - 1 {
            PostHogSDK.shared.capture("picks_coach_finished", properties: ["last_step": index])
            onFinish()
        } else {
            withAnimation(.easeOut(duration: 0.2)) { index += 1 }
        }
    }
}
