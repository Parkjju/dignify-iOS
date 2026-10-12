import SwiftUI

/// 신규 유저 온보딩.
///
///     (로딩) → 인기곡 풀에서 곡 고르기 → 피드 구성 중 → 피드(코치마크)
///
/// 장르를 한 번도 묻지 않는다. 장르 이름으로 자기 취향을 말할 수 있는 사람은 많지 않고,
/// 물어봐야 나오는 건 `user_genres` 몇 행뿐이라 첫 피드가 여전히 무작위였다.
/// 고른 곡을 그대로 하입하면 산출물이 시드가 되어 첫 피드부터 무드 정렬이 걸린다.
///
/// 튜토리얼 카드는 feed_coachmark 1.0에서 뺐다 — 피드 조작은 피드 위 제스처 코치마크가 가르친다.
///
/// 풀이 비어도(네트워크 실패·서버 미시딩) 고르기 화면으로 넘긴다 — 화면이 빈 그리드와 건너뛰기 버튼을 준다.
/// 여기서 조용히 완료 처리를 해버리면 그 요청이 실패했을 때 다시 시도할 자리가 없다.
struct NewUserOnboardingView: View {
    @Environment(AppSession.self) private var appSession
    @State private var pool: [API.FeedItem]?
    /// 고르기를 마치고 첫 피드를 기다리는 중. 고른 곡 커버를 보여 준다.
    @State private var building: [URL?]?

    /// 피드 구성 중을 적어도 이만큼은 보여 준다 — 응답이 먼저 와도 화면이 번쩍이고 사라지지 않게.
    private static let minBuildingTime: Duration = .seconds(1)

    var body: some View {
        Group {
            if let building {
                FeedBuildingView(covers: building)
            } else if let pool {
                SeedPoolPickerView(pool: pool) { picked in try await complete(picked) }
            } else {
                // 둘러보기 후 로그인이면 인디케이터를 붙인다. 바로 로그인은 로고만(feed_coachmark 1.1 #8).
                LaunchLoadingView(showsProgress: appSession.signedInFromGuest)
            }
        }
        .transition(.opacity)
        .background(DSColor.background)
        .task { pool = await SeedPoolPickerView.fetch(appSession) }
    }

    /// 온보딩 완료를 서버에 알리고, 첫 피드를 받는 동안 「피드 구성 중」을 띄운 뒤 피드로 전환한다.
    /// 피드 응답은 `prefetchedFeed`로 넘긴다 — 피드가 같은 요청을 또 보내지 않는다.
    /// 피드를 못 받아도 그대로 넘어간다. 피드 화면이 자기 재시도 버튼을 갖고 있다.
    private func complete(_ picked: [API.FeedItem]) async throws {
        try await appSession.api.send(.completeOnboarding)
        withAnimation(.easeOut(duration: 0.25)) {
            building = picked.map { $0.artworkUrl.itunesArtworkURL(size: 300) }
        }
        async let minimum: Void = Task.sleep(for: Self.minBuildingTime)
        let feed = try? await appSession.api.send(.feed(), as: API.FeedResponse.self)
        try? await minimum
        appSession.prefetchedFeed = feed
        // 업데이트 유저용 1회 트리거(MainTabView)가 이 유저에게 또 걸리지 않게 같이 내린다.
        UserDefaults.standard.set(true, forKey: "didSoundRounds")
        // MainTabView가 이 플래그로 "방금 가입한 유저"를 알아본다(What's New 오발동 방지).
        UserDefaults.standard.set(true, forKey: "didJustOnboard")
        withAnimation(.easeOut(duration: 0.25)) {
            appSession.authState = .signedIn
        }
    }
}
