import SwiftUI

/// 신규 유저 온보딩.
///
///     튜토리얼 → 소리 2지선다 3라운드 → 피드
///
/// 장르를 한 번도 묻지 않는다. 장르 이름으로 자기 취향을 말할 수 있는 사람은 많지 않고,
/// 물어봐야 나오는 건 `user_genres` 몇 행뿐이라 첫 피드가 여전히 무작위였다.
/// 고른 곡을 그대로 하입하면 산출물이 시드가 되어 첫 피드부터 무드 정렬이 걸린다.
///
/// 후보를 못 받으면(네트워크 실패·서버 미시딩) 라운드를 건너뛰고 바로 완료로 간다.
/// 온보딩이 막히는 것보다 시드 없이 시작하는 편이 낫다 — 그 유저는 콜드스타트 피드가 받는다.
struct NewUserOnboardingView: View {
    @Environment(AppSession.self) private var appSession
    @State private var rounds: [API.OnboardingCandidates.Round] = []
    @State private var isLoading = true
    @State private var showRounds = false
    /// 튜토리얼이 끝났는데 후보가 아직 안 온 상태. 이때는 화면을 튜토리얼 마지막 장에 두고
    /// 응답을 기다린다 — 빈 라운드 화면을 잠깐 보여주는 것보다 낫다.
    @State private var waitingForRounds = false

    var body: some View {
        Group {
            if showRounds {
                SoundRoundsView(rounds: rounds) { _ in try await complete() }
            } else {
                // 피드 조작을 먼저 익히게 한다. 후보 곡은 이 동안 백그라운드로 받는다.
                TutorialView { finishTutorial() }
            }
        }
        .background(DSColor.background)
        .task {
            rounds = await SoundRoundsView.fetch(appSession)
            isLoading = false
            // 튜토리얼을 먼저 끝냈으면(= 기다리는 중) 여기서 갈린다.
            if waitingForRounds { enterRounds() }
        }
    }

    private func finishTutorial() {
        if isLoading { waitingForRounds = true; return }
        enterRounds()
    }

    /// 후보가 비어도 그대로 넘긴다 — `SoundRoundsView`가 마지막 화면부터 시작해 완료 버튼을 준다.
    /// 여기서 조용히 완료 처리를 해버리면 그 요청이 실패했을 때 다시 시도할 자리가 없다.
    private func enterRounds() {
        waitingForRounds = false
        showRounds = true
    }

    /// 온보딩 완료를 서버에 알리고 피드로 전환한다.
    private func complete() async throws {
        try await appSession.api.send(.completeOnboarding)
        // 업데이트 유저용 1회 트리거(MainTabView)가 이 유저에게 또 걸리지 않게 같이 내린다.
        UserDefaults.standard.set(true, forKey: "didSoundRounds")
        // MainTabView가 이 플래그로 "방금 가입한 유저"를 알아본다(What's New 오발동 방지).
        UserDefaults.standard.set(true, forKey: "didJustOnboard")
        appSession.authState = .signedIn
    }
}
