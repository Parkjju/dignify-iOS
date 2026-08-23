import SwiftUI
import PostHog

/// 소리 2지선다 라운드. 두 곡을 듣고 끌리는 쪽을 고르면 **그 곡을 그대로 하입한다** —
/// 산출물이 무드 시드라 다음 피드부터 그 방향으로 정렬된다.
///
/// 신규 가입(온보딩)과 기존 유저(업데이트 후 1회)가 같은 화면을 쓴다. 다른 건 끝난 뒤에 할 일뿐이라
/// `onFinish`로 넘긴다 — 온보딩은 서버에 완료를 알리고, 기존 유저는 커버만 닫는다.
/// 후보를 못 받는 경우는 이 뷰가 모른다. 부르는 쪽이 `fetch`로 먼저 받아 보고 비면 안 띄운다.
struct SoundRoundsView: View {
    let rounds: [API.OnboardingCandidates.Round]

    /// 라운드가 다 끝나고 마지막 버튼을 눌렀을 때. 인자는 실제로 고른 곡 수(전부 건너뛰면 0).
    /// 던지면 마지막 화면에 에러가 남고 버튼은 다시 눌린다.
    var onFinish: (Int) async throws -> Void

    @Environment(AppSession.self) private var appSession
    @State private var audio = FeedAudioController()
    @State private var roundIndex = 0
    @State private var pickedCount = 0
    @State private var isDone: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(rounds: [API.OnboardingCandidates.Round], onFinish: @escaping (Int) async throws -> Void) {
        self.rounds = rounds
        self.onFinish = onFinish
        // 후보가 없으면 보여줄 라운드도 없다. 마지막 화면부터 시작해 "하입이 피드를 만든다"는
        // 한 줄만 남긴다 — 온보딩이 여기서 막히면 안 되고, 완료 버튼도 이 화면에 있다.
        _isDone = State(initialValue: rounds.isEmpty)
    }

    var body: some View {
        Group {
            if isDone { doneView } else { roundsView }
        }
        .background(DSColor.background)
        .onAppear { autoPlayFirst() }
        .onDisappear { audio.stop() }
    }

    /// 부르는 쪽에서 미리 받아 둔다. 실패·빈 응답은 빈 배열로 뭉갠다 — 라운드를 못 보여주는 건
    /// 막을 일이 아니라 건너뛸 일이다(그 유저는 콜드스타트 피드가 받는다).
    static func fetch(_ session: AppSession) async -> [API.OnboardingCandidates.Round] {
        let res = try? await session.api.send(.onboardingCandidates, as: API.OnboardingCandidates.self)
        // 곡이 두 개 다 안 온 라운드는 2지선다가 성립하지 않는다.
        return (res?.rounds ?? []).filter { $0.items.count == 2 }
    }

    // MARK: - Rounds

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
                    doneCopy("Your picks shape the feed",
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

            Button { finish() } label: {
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
        // 이 화면이 네트워크에 인질로 잡힌다.
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
            isDone = true
        }
    }

    private func finish() {
        errorMessage = nil
        isSubmitting = true
        audio.stop()
        Task {
            defer { isSubmitting = false }
            do {
                try await onFinish(pickedCount)
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
