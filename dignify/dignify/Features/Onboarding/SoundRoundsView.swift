import SwiftUI
import PostHog

/// 소리 2지선다 라운드. 시작 화면 → 라운드 → 마지막 한 줄.
/// 두 곡을 듣고 끌리는 쪽을 고르면 **그 곡을 그대로 하입한다** — 산출물이 무드 시드라
/// 다음 피드부터 그 방향으로 정렬된다.
///
/// 신규 가입(온보딩)과 기존 유저(업데이트 후 1회)가 같은 화면을 쓴다. 다른 건 끝난 뒤에 할 일뿐이라
/// `onFinish`로 넘긴다 — 온보딩은 서버에 완료를 알리고, 기존 유저는 커버만 닫는다.
/// 후보를 못 받는 경우는 이 뷰가 모른다. 부르는 쪽이 `fetch`로 먼저 받아 보고 비면 안 띄운다.
struct SoundRoundsView: View {
    let rounds: [API.OnboardingCandidates.Round]

    /// 업데이트로 들어온 기존 유저인가. 시작 화면에 "왜 지금 이게 떴는지" 한 줄이 더 붙는다 —
    /// 신규 가입자는 튜토리얼 끝에 이어서 보므로 그 줄이 필요 없다.
    var isUpdate = false

    /// 라운드가 다 끝나고 마지막 버튼을 눌렀을 때. 인자는 실제로 고른 곡 수(전부 건너뛰면 0).
    /// 던지면 마지막 화면에 에러가 남고 버튼은 다시 눌린다.
    var onFinish: (Int) async throws -> Void

    @Environment(AppSession.self) private var appSession
    @State private var audio = FeedAudioController()
    @State private var didStart = false
    @State private var roundIndex = 0
    /// 이번 라운드에서 고른 곡. 라운드를 넘길 때 비운다. nil이면 하단 버튼이 안 눌린다 —
    /// 기본 선택을 두면 아무것도 안 듣고 넘긴 유저의 곡이 시드가 된다.
    @State private var selected: API.FeedItem?
    /// 라운드마다 무엇을 골랐는지. 마지막 화면이 이걸 그대로 되짚어 준다 —
    /// 고른 걸 확인할 방법이 없으면 유저는 이 테스트가 실제로 쓰이는지 알 수 없다.
    @State private var picks: [Pick] = []

    /// 요약 한 줄. `isHigh`는 서버가 `highTrackId`를 안 줬으면 nil이라 극단 표시가 빠진다.
    struct Pick: Identifiable {
        let id: Int
        let axis: String
        let isHigh: Bool?
        let trackName: String
        let artistName: String
    }
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// 남은 라운드가 없으면 마지막 화면이다. **`@State`로 들지 않는다** — `init`에서
    /// `rounds.isEmpty`를 상태에 굳히면, SwiftUI가 배열이 채워지기 전에 뷰를 한 번 만들었을 때
    /// 그 값이 그대로 남아 후보가 있어도 마지막 화면이 뜬다(실제로 밟았다).
    /// 후보가 0개면 처음부터 여기라 온보딩이 막히지 않는다.
    private var isDone: Bool { roundIndex >= rounds.count }

    var body: some View {
        Group {
            if !didStart {
                introView
            } else if isDone {
                doneView
            } else {
                roundsView
            }
        }
        .background(DSColor.background)
        .onAppear {
            // 이 화면이 소리를 내는 동안 아래 피드는 멈춰 있어야 한다(커버는 탭을 안 바꾼다).
            appSession.modalAudioActive = true
        }
        .onDisappear {
            audio.stop()
            appSession.modalAudioActive = false
        }
    }

    /// 부르는 쪽에서 미리 받아 둔다. 실패·빈 응답은 빈 배열로 뭉갠다 — 라운드를 못 보여주는 건
    /// 막을 일이 아니라 건너뛸 일이다(그 유저는 콜드스타트 피드가 받는다).
    static func fetch(_ session: AppSession) async -> [API.OnboardingCandidates.Round] {
        do {
            let res = try await session.api.send(.onboardingCandidates, as: API.OnboardingCandidates.self)
            // 곡이 두 개 다 안 온 라운드는 2지선다가 성립하지 않는다.
            let rounds = res.rounds.filter { $0.items.count == 2 }
            #if DEBUG
            print("[rounds] 후보 \(res.rounds.count)라운드 중 \(rounds.count)라운드 사용")
            #endif
            return rounds
        } catch {
            // 실패해도 라운드를 건너뛸 뿐이라 화면엔 아무 말도 안 남는다. 그래서 여기 로그가 필요하다
            // — 서버가 안 줬는지, 디코딩이 깨졌는지가 콘솔에서만 갈린다.
            #if DEBUG
            print("[rounds] 후보를 못 받았다: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Intro

    /// 라운드가 아무 말 없이 뜨면 유저는 이게 왜 떴는지, 뭘 고르는 건지 모른 채 답을 찍는다.
    /// 업데이트 유저에겐 특히 그렇다 — 자기가 요청한 적 없는 화면이 앱을 켜자마자 덮는다.
    private var introView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image("HypeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text("What sounds good to you?")
                    .font(DSTypography.title1)
                    .tracking(-0.48)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                if isUpdate {
                    Text("Your feed follows the tracks you hype now. Let's set the first direction together.")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                Text("Rather than ask, we'll just play. Two clips at a time — pick the one you'd rather keep listening to. There's no right answer, and whatever you pick gets hyped.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Text("Asked in words, taste turns into genre names. Sound is the more honest question.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                Text("Three rounds and you're done. Neither one? Skip it.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            Spacer()

            Button { start() } label: { Text("Get started") }
                .buttonStyle(DSPrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Rounds

    /// 이 라운드가 무엇을 묻는지. 서버는 축 이름만 주고 설명은 앱이 붙인다 — 카피 톤과 번역이
    /// 문자열 카탈로그에 있어야 하기 때문이다. **어느 카드가 어느 극단인지는 말하지 않는다.**
    /// 말하는 순간 유저는 소리가 아니라 라벨을 고른다.
    ///
    /// 모르는 축이 오면(서버가 축을 늘렸는데 앱이 옛 버전) 일반 문구로 떨어진다. 라운드는 그대로 돈다.
    private var axisCopy: (question: LocalizedStringKey, poles: LocalizedStringKey)? {
        switch round?.axis {
        case "arousal":
            return ("Which energy pulls you in?", "One of them drives hard, the other stays calm.")
        case "lofi":
            return ("Which texture pulls you in?", "One is raw and noisy, the other is clean and polished.")
        case "valence":
            return ("Which mood pulls you in?", "One is bright and up, the other is dark and heavy.")
        default:
            return nil
        }
    }

    private var round: API.OnboardingCandidates.Round? { rounds[safe: roundIndex] }

    /// 이 곡이 축의 어느 극단인지. 서버가 `highTrackId`를 안 줬으면 nil이라 표시가 통째로 빠진다.
    private func pole(of item: API.FeedItem) -> Bool? {
        guard let high = round?.highTrackId else { return nil }
        return item.trackId == high
    }

    /// 축 이름 — 요약에서 왼쪽 열에 선다.
    private func axisName(_ axis: String) -> LocalizedStringKey? {
        switch axis {
        case "arousal": return "Energy"
        case "lofi": return "Texture"
        case "valence": return "Mood"
        default: return nil
        }
    }

    /// 고른 쪽을 사람 말로. **고른 뒤에만 보여준다.**
    private func poleLabel(_ axis: String, isHigh: Bool) -> LocalizedStringKey? {
        switch (axis, isHigh) {
        case ("arousal", true): return "the driving one"
        case ("arousal", false): return "the calm one"
        case ("lofi", true): return "the raw one"
        case ("lofi", false): return "the clean one"
        case ("valence", true): return "the bright one"
        case ("valence", false): return "the dark one"
        default: return nil
        }
    }

    private var roundsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "\(roundIndex + 1) / \(rounds.count)")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                Spacer()
                Button("Skip") { skipRound() }
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .frame(height: 44)
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(axisCopy?.question ?? "Which one pulls you in?")
                    .font(DSTypography.title1)
                    .tracking(-0.48)
                    .foregroundStyle(DSColor.textPrimary)
                if let poles = axisCopy?.poles {
                    Text(poles)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Tap a card to hear it, then hit Next.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 16)

            if let round = rounds[safe: roundIndex] {
                VStack(spacing: 16) {
                    ForEach(round.items, id: \.trackId) { item in
                        candidateCard(item)
                    }
                }
                .padding(.horizontal, 24)
                // 라운드가 바뀌면 카드가 새로 그려지게 한다(이전 카드의 재생 표시가 남지 않게).
                .id(roundIndex)
            }

            Spacer(minLength: 24)

            Button { advance() } label: { Text("Next") }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(selected == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    /// 탭 = 이 곡을 고르면서 듣기. 같은 카드를 다시 누르면 재생만 토글한다.
    /// 넘기는 건 하단 버튼이 한다 — 카드가 선택이자 페이지 넘김이면 뭘 누른 건지 알 수 없다.
    private func candidateCard(_ item: API.FeedItem) -> some View {
        let isSelected = selected?.trackId == item.trackId
        let isPlaying = audio.activeTrackId == item.trackId && !audio.isPaused

        return Button {
            choose(item)
        } label: {
            HStack(spacing: 14) {
                RemoteImage(url: URL(string: item.artworkUrl)) { DSColor.surface }
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.trackName)
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    // 고르기 전엔 극단을 숨긴다 — 알려주면 소리가 아니라 라벨을 고른다.
                    // 고른 뒤엔 반대다. 뭘 고른 건지 그 자리에서 알아야 마지막 요약이 처음 보는 말이 아니게 된다.
                    if isSelected, let label = pole(of: item).flatMap({ poleLabel(round?.axis ?? "", isHigh: $0) }) {
                        Text(label)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.brand)
                            .lineLimit(1)
                    } else {
                        Text(verbatim: item.artistName)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill"
                                             : (isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected || isPlaying ? DSColor.brand : DSColor.textTertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .stroke(isSelected ? DSColor.brand : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(PressScaleStyle())
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()
            // 삼항으로 묶지 않는다 — 문자열 카탈로그 추출이 조용히 한쪽을 빠뜨릴 수 있다.
            if picks.isEmpty {
                VStack(spacing: 14) {
                    Image("HypeIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                    doneCopy("Your hypes shape the feed",
                             "Hype anything you like and the next cards follow you.")
                }
            } else {
                summaryView
            }
            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            Button { finish() } label: {
                if isSubmitting { ProgressView().tint(.white) } else { Text("Start digging") }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    /// 고른 것을 그대로 되짚어 준다 — 축, 고른 쪽, 그리고 곡 이름.
    ///
    /// 곡 이름이 있어야 "아까 그 곡이 맞다"가 눈으로 확인되고, 축과 극단이 붙어야 무작위로 보여준 게
    /// 아니라는 게 성립한다. 주장만 남기면(=예전 문구) 유저는 이 테스트가 실제로 쓰이는지 알 수 없다.
    private var summaryView: some View {
        VStack(spacing: 20) {
            Text("Here's what you picked")
                .font(DSTypography.title1)
                .tracking(-0.48)
                .foregroundStyle(DSColor.textPrimary)

            VStack(spacing: 12) {
                ForEach(picks) { pick in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let name = axisName(pick.axis) {
                            Text(name)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColor.textTertiary)
                                .frame(width: 52, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let isHigh = pick.isHigh, let label = poleLabel(pick.axis, isHigh: isHigh) {
                                Text(label)
                                    .font(DSTypography.bodyMedium)
                                    .foregroundStyle(DSColor.brand)
                            }
                            Text(verbatim: "\(pick.trackName) · \(pick.artistName)")
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.medium))

            Text("All hyped. Your feed starts from here, and turns as you keep hyping.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private func doneCopy(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(DSTypography.title1)
                .tracking(-0.48)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Actions

    private func start() {
        didStart = true
        autoPlayFirst()
    }

    private func play(_ item: API.FeedItem) {
        guard let url = URL(string: item.previewUrl) else { return }
        audio.togglePreview(trackId: item.trackId, url: url)
    }

    /// 라운드에 들어오면 A를 자동 재생한다(선택은 안 한다). 첫 소리까지 탭을 요구하면
    /// 아무것도 안 듣고 넘기는 유저가 생긴다.
    private func autoPlayFirst() {
        guard let first = rounds[safe: roundIndex]?.items.first else { return }
        play(first)
    }

    /// 카드 탭 — 고르면서 듣는다. 같은 카드를 다시 누르면 재생만 토글한다.
    /// **하입은 여기서 보내지 않는다.** 마음이 바뀌어 다른 카드를 누르면 안 고른 곡까지
    /// 시드가 되기 때문이다. 실제 전송은 라운드를 넘길 때(`advance`) 한 번만 한다.
    private func choose(_ item: API.FeedItem) {
        if selected?.trackId == item.trackId {
            audio.toggleCurrentPlayback()
            return
        }
        selected = item
        play(item)
    }

    private func skipRound() {
        PostHogSDK.shared.capture("onboarding_sound_skipped", properties: [
            "round": roundIndex,
            "axis": round?.axis ?? "",
        ])
        selected = nil
        advance()
    }

    /// 고른 곡을 하입하고 다음 라운드로. 건너뛰기는 `selected`가 nil이라 하입 없이 지나간다.
    private func advance() {
        if let item = selected {
            picks.append(Pick(id: item.trackId, axis: round?.axis ?? "", isHigh: pole(of: item),
                              trackName: item.trackName, artistName: item.artistName))
            PostHogSDK.shared.capture("onboarding_sound_picked", properties: [
                "round": roundIndex,
                "axis": round?.axis ?? "",
                "pole": pole(of: item).map { $0 ? "HIGH" : "LOW" } ?? "",
                "track_id": item.trackId,
            ])
            // 하입은 결과를 기다리지 않는다. 실패해도 시드가 하나 줄 뿐이고, 여기서 막으면
            // 이 화면이 네트워크에 인질로 잡힌다.
            appSession.hypeState[item.trackId] = true
            Task { try? await appSession.api.send(.hype(trackId: item.trackId)) }
        }
        audio.stop()
        selected = nil
        roundIndex += 1
        if isDone {
            PostHogSDK.shared.capture("onboarding_sound_completed", properties: ["picked": picks.count])
        } else {
            autoPlayFirst()
        }
    }

    private func finish() {
        errorMessage = nil
        isSubmitting = true
        audio.stop()
        Task {
            defer { isSubmitting = false }
            do {
                try await onFinish(picks.count)
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
            }
        }
    }
}

/// 눌림 피드백만 주는 스타일. DSPrimaryButtonStyle은 색·높이가 고정이라 카드 안엔 안 맞는다.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Array {
    /// 라운드 인덱스가 후보 개수보다 앞서가는 순간이 실제로 있다(라운드가 0개일 때).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
