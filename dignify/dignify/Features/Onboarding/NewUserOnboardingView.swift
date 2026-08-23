import SwiftUI
import PostHog

/// 신규 유저 온보딩.
///
///     튜토리얼 → 소리 2지선다 3라운드 → 시작
///
/// 장르를 한 번도 묻지 않는다. 장르 이름으로 자기 취향을 말할 수 있는 사람은 많지 않고,
/// 물어봐야 나오는 건 `user_genres` 몇 행뿐이라 첫 피드가 여전히 무작위였다.
/// 고른 곡을 **그대로 하입**하면 산출물이 시드가 되어 첫 피드부터 무드 정렬이 걸린다.
///
/// 후보를 못 받으면(네트워크 실패·서버 미배포) 라운드를 통째로 건너뛴다. 온보딩이 막히는 것보다
/// 시드 없이 시작하는 편이 낫다 — 그 유저는 콜드스타트 피드가 받는다.
struct NewUserOnboardingView: View {
    enum Step: Equatable { case tutorial, rounds, done }

    /// 프리뷰용 고정 후보. 앱 경로에선 항상 nil.
    var previewRounds: [API.OnboardingCandidates.Round]?

    @Environment(AppSession.self) private var appSession
    @State private var step: Step
    @State private var audio = FeedAudioController()

    @State private var rounds: [API.OnboardingCandidates.Round] = []
    @State private var roundIndex = 0
    @State private var pickedCount = 0
    @State private var isLoading = true

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(previewRounds: [API.OnboardingCandidates.Round]? = nil, initialStep: Step = .tutorial) {
        self.previewRounds = previewRounds
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        Group {
            switch step {
            case .tutorial:
                // 피드 조작을 먼저 익히게 한다. 후보 곡은 이 동안 백그라운드로 받는다.
                TutorialView { startRounds() }
            case .rounds:
                roundsView
            case .done:
                doneView
            }
        }
        .background(DSColor.background)
        .task { await loadCandidates() }
        .onDisappear { audio.stop() }
    }

    // MARK: - Rounds

    private var roundsView: some View {
        VStack(spacing: 0) {
            HStack {
                if !rounds.isEmpty {
                    Text(verbatim: "\(roundIndex + 1) / \(rounds.count)")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                Spacer()
                Button("Skip") { skipRound() }
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .frame(height: 44)
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Which one pulls you in?")
                    .font(DSTypography.title1)
                    .tracking(-0.48)
                    .foregroundStyle(DSColor.textPrimary)
                Text("Tap a card to hear it. Pick whichever you'd keep listening to.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 16)

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let round = rounds[safe: roundIndex] {
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
        }
    }

    private func candidateCard(_ item: API.FeedItem) -> some View {
        let isActive = audio.activeTrackId == item.trackId
        let isPlaying = isActive && !audio.isPaused

        return VStack(spacing: 0) {
            Button {
                play(item)
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
                        Text(verbatim: item.artistName)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isActive ? DSColor.brand : DSColor.textTertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())

            Divider().overlay(DSColor.divider)

            Button {
                choose(item)
            } label: {
                Text("Pick this one")
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.brand)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
        }
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.medium)
                .stroke(isActive ? DSColor.brand : .clear, lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image("HypeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                // 삼항으로 묶지 않는다 — 문자열 카탈로그 추출이 조용히 한쪽을 빠뜨릴 수 있다.
                if pickedCount > 0 {
                    doneCopy("Your picks shape the first feed",
                             "We hyped what you picked. Keep hyping and the feed follows you.")
                } else {
                    doneCopy("Your hypes shape the feed",
                             "Hype anything you like and the next cards follow you.")
                }
            }
            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            Button { submit() } label: {
                if isSubmitting { ProgressView().tint(.white) } else { Text("Start digging") }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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

    private func loadCandidates() async {
        if let previewRounds {
            rounds = previewRounds
            isLoading = false
            return
        }
        guard rounds.isEmpty else { return }   // 스텝이 바뀌어 .task가 다시 돌아도 재요청하지 않는다.
        let res = try? await appSession.api.send(.onboardingCandidates,
                                                 as: API.OnboardingCandidates.self)
        // 곡이 두 개 다 안 온 라운드는 2지선다가 성립하지 않는다.
        rounds = (res?.rounds ?? []).filter { $0.items.count == 2 }
        isLoading = false
        // 응답이 튜토리얼보다 늦게 오는 경우 — 이미 라운드 화면에 서 있으므로 여기서 갈린다.
        guard step == .rounds else { return }
        if rounds.isEmpty { step = .done } else { autoPlayFirst() }
    }

    /// 튜토리얼이 끝났을 때. 후보가 아직이면 로딩 상태로 라운드 화면에 세워 두고
    /// `loadCandidates`가 도착 시점에 갈라 준다.
    private func startRounds() {
        if isLoading { step = .rounds; return }
        step = rounds.isEmpty ? .done : .rounds
        if !rounds.isEmpty { autoPlayFirst() }
    }

    private func play(_ item: API.FeedItem) {
        guard let url = URL(string: item.previewUrl) else { return }
        audio.togglePreview(trackId: item.trackId, url: url)
    }

    /// 라운드에 들어오면 A를 자동 재생한다. 첫 소리까지 탭을 요구하면 아무것도 안 듣고
    /// 고르는 유저가 생기고, 그러면 시드가 취향과 무관해진다.
    private func autoPlayFirst() {
        guard let first = rounds[safe: roundIndex]?.items.first else { return }
        play(first)
    }

    private func choose(_ item: API.FeedItem) {
        pickedCount += 1
        PostHogSDK.shared.capture("onboarding_sound_picked", properties: [
            "round": roundIndex,
            "axis": rounds[safe: roundIndex]?.axis ?? "",
            "track_id": item.trackId,
        ])
        // 하입은 결과를 기다리지 않는다. 실패해도 시드가 하나 줄 뿐이고, 여기서 막으면
        // 온보딩이 네트워크에 인질로 잡힌다.
        appSession.hypeState[item.trackId] = true
        Task { try? await appSession.api.send(.hype(trackId: item.trackId)) }
        advance()
    }

    private func skipRound() {
        PostHogSDK.shared.capture("onboarding_sound_skipped", properties: [
            "round": roundIndex,
            "axis": rounds[safe: roundIndex]?.axis ?? "",
        ])
        advance()
    }

    private func advance() {
        audio.stop()
        if roundIndex + 1 < rounds.count {
            roundIndex += 1
            autoPlayFirst()
        } else {
            PostHogSDK.shared.capture("onboarding_sound_completed", properties: ["picked": pickedCount])
            step = .done
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        audio.stop()
        Task {
            defer { isSubmitting = false }
            do {
                try await appSession.api.send(.completeOnboarding)
                // MainTabView가 이 플래그로 "방금 가입한 유저"를 알아본다(What's New 오발동 방지).
                UserDefaults.standard.set(true, forKey: "didJustOnboard")
                appSession.authState = .signedIn
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
    /// 라운드 인덱스가 후보 개수보다 앞서가는 순간이 실제로 있다(응답이 늦게 오거나 라운드가 0개).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
