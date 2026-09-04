import SwiftUI
import PostHog
import StoreKit

/// 피드가 무엇을 재생하는가. 재생·하입·상세·공유·청취 계측이 전부 여기 있어서
/// 픽 재생도 두 번째 플레이어를 만들지 않고 이 화면을 모드로 갈라 쓴다.
enum FeedMode: Equatable {
    case normal
    /// 픽 탭에서 fullScreenCover로 덮는다. 목록 스크롤이 살아있고 닫기가 공짜다.
    case pick(id: Int, nickname: String)
}

struct FeedView: View {
    /// .pick이면 검색바·큐레이션 세트·커서 영속화·페이지네이션이 전부 꺼진다.
    var mode: FeedMode = .normal

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    /// 리뷰 요청은 설치당 한 번뿐. 앱을 지웠다 깔면 초기화된다(유일한 재노출 경로).
    @AppStorage("didAskReview") private var didAskReview = false
    /// 피드 코치마크를 이미 봤는지. 하입 버튼이 무엇을 하는지 모르면 이 앱은 그냥 재생기다.
    @AppStorage("seenFeedCoach") private var seenFeedCoach = false
    @State private var audio = FeedAudioController()
    @State private var feedList: [Feed] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var nextCursor: String?
    @State private var isPaging = false
    /// 앱 재구동 후 이어보기용으로 마지막 일반 피드 커서를 저장. 비면 처음부터(새 시드).
    @AppStorage("feedCursor") private var savedFeedCursor = ""
    /// 피드 맨 앞에 붙은 이번 주 큐레이션 곡 수. 0이면 세트가 없거나 이미 완주한 세트.
    @State private var curationCount = 0
    /// 지금 앞세운 세트의 식별자. 완주 시점에 seenCurationSet으로 옮겨 적는다.
    @State private var curationSetKey = ""
    /// 완주한 세트 키. 같은 세트를 매 진입마다 다시 앞세우지 않기 위한 기억.
    @AppStorage("seenCurationSet") private var seenCurationSet = ""
    /// 푸시 권한 자체 안내를 이미 한 번 보여줬는지. 시스템 팝업과 달리 이건 우리가 센다.
    @AppStorage("didOfferPush") private var didOfferPush = false
    @State private var showPushOffer = false
    @State private var searchText: String = ""
    @State private var isSearching = false
    @State private var searchFocused = false
    /// 확정된 검색어(빈 문자열이면 일반 피드). 비어있지 않으면 feedList는 검색 결과다.
    @State private var activeQuery = ""
    /// 검색 진입 시 일반 피드 상태를 보관 → 검색 종료 시 복원(재페치 없이).
    @State private var savedFeed: FeedSnapshot?
    /// 최근 검색 최대 5개. @AppStorage는 배열 미지원이라 개행으로 join.
    /// ponytail: 단일 라인 TextField라 검색어에 개행이 안 들어와 안전.
    @AppStorage("recentSearches") private var recentRaw = ""
    @State private var offset: CGFloat = 0
    /// 미리 받아둘 카드 수. 오디오 슬라이딩 윈도우와 같은 발상이고, 이미지가 더 싸서 조금 넓다.
    private static let prefetchWindow = 8

    @State private var currentIndex = 0
    /// 이미 미리 받은 트랙. 스크롤할 때마다 같은 URL을 다시 열지 않으려고 든다.
    /// 피드를 갈아끼워도 안 비운다 — 방금 받은 것을 또 받는 쪽이 손해다.
    @State private var prefetchedTrackIds: Set<Int> = []
    /// track_viewed 중복 방지 — 탭 복귀 등으로 같은 트랙이 다시 current가 돼도 한 번만 찍는다.
    @State private var lastViewedTrackId: Int?
    @State private var detailTarget: DetailTarget?
    @State private var shareItem: ShareItem?
    @State private var showRequestSheet = false
    @State private var toastMessage: String?
    /// 장르 소진 토스트를 피드 세션당 한 번만 노출하기 위한 플래그.
    @State private var genreExhaustedShown = false
    @State private var showsHypeBurst = false
    @State private var burstLocation: CGPoint = .zero
    @State private var burstConfetti: [ConfettiPiece] = []
    /// Read once on appear — reading UIKit window insets during body evaluation
    /// triggers a UIKit↔SwiftUI AttributeGraph cycle that freezes all touch input.
    @State private var safeInsets = EdgeInsets()

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first { $0.isKeyWindow }
    }

    /// 리뷰를 묻기 전에 이번 실행에서 넘겨야 하는 카드 수(누적 아님).
    /// 실측 세션 분포는 청취 기준 p50=4·p75=9인데 스와이프 분포는 아직 안 봤다 —
    /// 15가 어느 백분위인지 모르므로, `review_prompt_requested` 수를 DAU와 비교해 조정한다.
    private static let reviewViewThreshold = 15

    private func resolveSafeInsets() {
        let i = keyWindow?.safeAreaInsets ?? .zero
        safeInsets = EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    // MARK: - Feed loading

    /// 첫 진입 페치. 재진입 시 이미 로드돼 있으면 건너뛴다(force로 재시도).
    /// 백엔드 커서는 시드+오프셋을 담아, 저장해둔 커서로 이어보면 앱 재구동 후에도
    /// 같은 순서로 이어진다. cursor=nil이면 새 시드라 처음부터 다시 나온다.
    private func loadInitialFeed(force: Bool = false) async {
        guard force || feedList.isEmpty else { return }
        if case .pick(let id, _) = mode {
            await loadPick(id: id)
            return
        }
        isLoading = true
        loadFailed = false
        genreExhaustedShown = false   // 새 피드 세션이므로 소진 토스트 다시 허용.
        do {
            let saved = savedFeedCursor.isEmpty ? nil : savedFeedCursor
            var res = try await session.api.send(.feed(cursor: saved), as: API.FeedResponse.self)
            // 저장된 커서가 소진/무효(빈 결과)면 새 세션으로 폴백.
            if res.items.isEmpty, saved != nil {
                savedFeedCursor = ""
                res = try await session.api.send(.feed(), as: API.FeedResponse.self)
            }
            feedList = await curationPrefix() + res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = res.hasMore ? res.nextCursor : nil
            savedFeedCursor = nextCursor ?? ""   // 소진되면 비워 다음 세션은 새 시드로.
            prefetchArtwork(from: currentIndex)
            // 소진 토스트는 스크롤로 실제 소진(페이징)했을 때만. 첫 로드/장르 교체 직후엔 안 띄운다.
            // 피드 탭일 때만 오디오를 갱신한다 — 다른 탭에서 장르 변경으로 재fetch된 경우
            // 여기서 재생하면 안 되고, 탭 복귀 시 onChange(selectedTab)가 새 리스트로 세팅한다.
            if isOnScreen {
                audio.updateWindow(feeds: feedList, current: currentIndex)
            }
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    /// 픽 재생. 30곡 상한 덕에 한 응답에 다 오므로 커서도 페이지네이션도 없다.
    /// items가 피드와 같은 스키마라 매핑 없이 그대로 꽂는다.
    private func loadPick(id: Int) async {
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.pickDetail(id: id), as: API.PickDetail.self)
            feedList = res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = nil
            prefetchArtwork(from: currentIndex)
            // currentIndex가 0 그대로면 .onChange(of:currentIndex)가 안 터진다. 직접 갱신하지 않으면
            // 이전 화면의 player가 남아 그게 재생된다(loadSearch가 같은 함정을 기록해뒀다).
            audio.updateWindow(feeds: feedList, current: currentIndex)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    /// 이 뷰가 지금 화면을 갖고 있는가. 픽 모드는 fullScreenCover라 떠 있는 동안 항상 참이고,
    /// 그동안 selectedTab은 .picks라 밑에 깔린 일반 피드는 알아서 멈춰 있다.
    private var isOnScreen: Bool {
        // 위에 소리를 내는 커버가 떠 있으면 화면을 가진 게 아니다.
        if session.modalAudioActive { return false }
        if case .pick = mode { return true }
        return session.selectedTab == .feed
    }

    /// 이번 주 큐레이션 세트를 일반 피드 앞에 붙인다. 세트가 끝나면 그대로 일반 피드로
    /// 이어지므로 별도 화면도 종료 처리도 없다.
    ///
    /// 도달을 푸시에 의존하지 않는 게 핵심 — 푸시 권한이 없는 유저도 앱을 열면 세트부터 본다.
    /// 푸시로 들어온 경우엔 이미 완주한 세트라도 다시 앞세운다(눌렀는데 없으면 안 되므로).
    /// ponytail: 실패하면 그냥 일반 피드 — 큐레이션이 없다고 피드가 비면 안 된다.
    private func curationPrefix() async -> [Feed] {
        curationCount = 0
        curationSetKey = ""
        let fromPush = session.pendingCurationOpen
        session.pendingCurationOpen = false
        guard let set = try? await session.api.send(.curation, as: API.CurationResponse.self),
              !set.items.isEmpty,
              fromPush || set.setKey != seenCurationSet
        else { return [] }
        curationCount = set.items.count
        curationSetKey = set.setKey
        return set.items.map(Feed.init)
    }

    /// 끝 3장 이내로 접근하면 다음 페이지를 붙인다. 커서 소진 시 정지.
    /// ponytail: 페이징 실패는 조용히 무시 — 다음 스와이프에 재시도된다.
    private func loadMoreIfNeeded() async {
        guard let cursor = nextCursor, !isPaging,
              currentIndex >= feedList.count - 3 else { return }
        isPaging = true
        defer { isPaging = false }
        // 검색 중이면 같은 쿼리로 다음 페이지를, 아니면 일반 피드를 잇는다.
        let endpoint = activeQuery.isEmpty
            ? Endpoint.feed(cursor: cursor)
            : .search(query: activeQuery, cursor: cursor)
        guard let res = try? await session.api.send(endpoint, as: API.FeedResponse.self)
        else { return }
        let newFeeds = res.items.map(Feed.init)
        feedList.append(contentsOf: newFeeds)
        nextCursor = res.hasMore ? res.nextCursor : nil
        prefetchArtwork(from: currentIndex)
        // 일반 피드일 때만 커서 저장(검색 커서는 세션 한정이라 저장 안 함).
        if activeQuery.isEmpty {
            savedFeedCursor = nextCursor ?? ""
            maybeShowGenreExhausted(res)
        }
    }

    /// 페이지의 아트워크(600px)를 URLCache에 미리 데운다. 완료를 기다리지 않고 발사만 —
    /// URLSession이 호스트당 동시성을 큐잉하고, 슬롯 렌더 시 AsyncImage가 캐시 히트로 즉시 뜬다.
    /// 지금 카드 기준 앞쪽 몇 장만 미리 받는다.
    ///
    /// **페이지가 30곡이 되면서 통째로 당기면 안 된다(2026-08-24).** 600px 아트워크 30장을
    /// 한 번에 여는 셈이라 셀룰러에서 한 페이지분 데이터를 다 쓰는데, 그중 대부분은 유저가
    /// 보기 전에 피드를 나간다. 스크롤이 앞으로 갈 때마다 창이 따라가므로 체감은 같다.
    private func prefetchArtwork(from index: Int) {
        for feed in feedList.dropFirst(max(0, index)).prefix(Self.prefetchWindow)
        where !prefetchedTrackIds.contains(feed.trackId) {
            guard let url = feed.artworkURL(size: 600) else { continue }
            prefetchedTrackIds.insert(feed.trackId)
            URLSession.shared.dataTask(with: url).resume()
        }
    }

    /// 로그인 유저(=장르 보유)의 피드가 장르 풀을 소진하면 세션당 한 번 토스트로 안내.
    /// 게스트는 장르가 없어 항상 exhausted라 제외한다.
    private func maybeShowGenreExhausted(_ res: API.FeedResponse) {
        guard res.genreExhausted == true, !genreExhaustedShown,
              session.authState == .signedIn else { return }
        genreExhaustedShown = true
        // GENRE 풀이 마르면 그 뒤로는 장르 무관 랜덤이 된다 = "장르 우선"이 실질적으로 꺼진다.
        // 세션당 한 번만 남긴다(페이지마다 찍으면 헤비 유저가 집계를 삼킨다).
        // views가 소진까지의 뎁스 — 이게 작으면 장르 풀이 얕다는 뜻이다.
        PostHogSDK.shared.capture("genre_exhausted",
                                  properties: ["views": session.sessionTrackViews])
        toastMessage = String(localized: "More beyond your genres")
        Task {
            try? await Task.sleep(for: .seconds(3))
            toastMessage = nil
        }
    }

    /// 큐레이션 상태(count/setKey)까지 담는다 — 검색 중엔 feedList가 검색 결과라
    /// 큐레이션 배지도 완주 판정도 성립하지 않는다. 검색 종료 시 그대로 되돌린다.
    private struct FeedSnapshot {
        var list: [Feed]; var index: Int; var cursor: String?
        var curationCount: Int; var curationSetKey: String
    }

    private var recentSearches: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    private func addRecentSearch(_ query: String) {
        var list = recentSearches.filter { $0 != query }
        list.insert(query, at: 0)
        recentRaw = list.prefix(5).joined(separator: "\n")
    }

    private func removeRecentSearch(_ query: String) {
        recentRaw = recentSearches.filter { $0 != query }.joined(separator: "\n")
    }

    private var previousFeed: Feed? {
        feedList.indices.contains(currentIndex - 1) ? feedList[currentIndex - 1] : nil
    }
    private var nextFeed: Feed? {
        feedList.indices.contains(currentIndex + 1) ? feedList[currentIndex + 1] : nil
    }

    private struct WindowedFeed: Identifiable {
        let feed: Feed
        let slot: Int
        var id: Int { feed.trackId }
    }

    private var windowedFeeds: [WindowedFeed] {
        var items: [WindowedFeed] = []
        if let previousFeed {
            items.append(WindowedFeed(feed: previousFeed, slot: -1))
        }
        if feedList.indices.contains(currentIndex) {
            items.append(WindowedFeed(feed: feedList[currentIndex], slot: 0))
        }
        if let nextFeed {
            items.append(WindowedFeed(feed: nextFeed, slot: 1))
        }
        return items
    }

    /// 피드가 실제로 떠 있고 가리킬 카드가 있을 때만. 검색 결과나 픽 재생 중에는 안 띄운다 —
    /// 그때는 하입 버튼이 있어도 "이 피드가 하입을 따라간다"는 설명이 맞지 않는다.
    private var showsCoach: Bool {
        !seenFeedCoach && mode == .normal && !isLoading && !feedList.isEmpty
            && activeQuery.isEmpty && !isSearching && detailTarget == nil
    }

    var body: some View {
        content
            .task { await loadInitialFeed() }
            // 게스트로 본 피드는 하입 제외가 안 된 상태(userId 없이 요청). 로그인되면
            // 새 시드로 다시 받아 교체한다. FeedView가 이미 떠 있는 게스트→signedIn만 해당
            // (정상 로그인 진입은 마운트 전 전환이라 여기 안 걸리고 .task가 처리).
            .onChange(of: session.authState) { _, newState in
                guard mode == .normal, newState == .signedIn else { return }
                activeQuery = ""
                savedFeed = nil
                savedFeedCursor = ""
                Task { await loadInitialFeed(force: true) }
            }
            // 앱이 떠 있는 채로 큐레이션 푸시를 탭한 경우. .task는 이미 끝났으므로
            // 여기서 다시 받아야 세트가 앞으로 온다(플래그는 curationPrefix가 내린다).
            // 소리를 내는 커버가 뜨고 지는 순간. 뜨면 멈추고, 닫히면 원래 트랙으로 되돌린다.
            .onChange(of: session.modalAudioActive) { _, active in
                if active {
                    audio.stop()
                } else if isOnScreen {
                    audio.updateWindow(feeds: feedList, current: currentIndex)
                }
            }
            // 소리 2지선다가 끝나면 시드가 새로 생긴 것이라 정렬 기준부터 다르다. 통째로 다시 받는다.
            .onChange(of: session.feedReloadToken) { _, _ in
                guard mode == .normal else { return }
                activeQuery = ""
                savedFeed = nil
                savedFeedCursor = ""
                Task { await loadInitialFeed(force: true) }
            }
            .onChange(of: session.pendingCurationOpen) { _, pending in
                guard mode == .normal, pending else { return }
                activeQuery = ""
                savedFeed = nil
                Task { await loadInitialFeed(force: true) }
            }
    }

    @ViewBuilder
    private var content: some View {
        // 전체 화면 로딩 스켈레톤은 보여줄 게 아예 없을 때(첫 진입)만. 검색 중엔
        // 기존 피드를 그대로 두고 결과가 오면 교체해 검은 화면 깜빡임을 없앤다.
        if isLoading && feedList.isEmpty {
            loadingView
        } else if feedList.isEmpty {
            emptyView
        } else {
            feed
        }
    }

    /// 로딩 스켈레톤 — 실제 카드 레이아웃(검은 배경 + 중앙 아트워크)과 맞춰
    /// 데이터 도착 시 전환이 튀지 않게 한다.
    private var loadingView: some View {
        GeometryReader { geo in
            let side = max(0, geo.size.width - 48)
            ZStack {
                Color.black
                DSShimmerView()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    private var emptyView: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Text(emptyMessage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if loadFailed {
                    Button("Try again") {
                        Task { activeQuery.isEmpty ? await loadInitialFeed(force: true)
                                                    : await loadSearch(activeQuery) }
                    }
                    .foregroundStyle(DSColor.brand)
                } else if !activeQuery.isEmpty {
                    Button("Request \"\(activeQuery)\"") {
                        if requireAccount() { showRequestSheet = true }
                    }
                    .foregroundStyle(DSColor.brand)
                    Button("Back to feed") { clearSearch() }
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showRequestSheet) {
            ArtistRequestSheet(prefill: activeQuery)
        }
    }

    private var emptyMessage: String {
        if loadFailed { return String(localized: "Couldn't load") }
        if !activeQuery.isEmpty { return String(localized: "No results for \"\(activeQuery)\"") }
        return String(localized: "No tracks to show")
    }

    private var feed: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .top) {
                // Paging layer — the ONE place gestures live. Slots overlap in
                // layout, so a single gesture here avoids multiple recognizers
                // fighting the system gesture gate (which froze all input).
                ZStack {
                    ForEach(windowedFeeds) { item in
                        feedSlot(for: item.feed, size: size)
                            .offset(y: CGFloat(item.slot) * size.height + offset)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(height: size.height))
                .simultaneousGesture(tapGestures(height: size.height))

                // 검색 중엔 피드 위에 최근 검색 패널을 덮고, 그 바깥 탭으로 검색 모드를 빠져나온다.
                if isSearching {
                    Color.black.opacity(0.001)   // 히트 테스트용 투명 배경.
                        .contentShape(Rectangle())
                        .onTapGesture { exitSearchMode() }
                    searchPanel
                        .padding(.top, safeInsets.top + 56)
                }

                searchOverlay(fullWidth: size.width - 32)
                    .padding(.horizontal, 16)
                    .padding(.top, safeInsets.top + 8)

                contextBadge

                if audio.isPaused && !isSearching {   // 검색 패널 아래에 가리도록 검색 중엔 숨김
                    Image(systemName: "play.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if showsHypeBurst {
                    HypeBurstView(isOn: feedList[currentIndex].isHyped, confetti: burstConfetti)
                        .position(burstLocation)
                }

                if let toastMessage {
                    // 상단 배치 — 트랙 타이틀/액션이 모두 하단에 있어 겹치지 않는다. 위에서 슬라이드로 등장.
                    Text(toastMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.8), in: Capsule())
                        .padding(.top, safeInsets.top + 64)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear {
            resolveSafeInsets()
            audio.onListen = { trackId in recordListen(trackId: trackId) }
            audio.onDwell = { trackId, seconds in logDwell(trackId: trackId, seconds: seconds) }
            audio.onPlaybackStart = { trackId, latency in
                logPlaybackStart(trackId: trackId, latency: latency)
            }
            audio.onRemoteSeek = { index in remoteSeek(to: index) }
            // Live Activity 하입 버튼 → 화면 탭과 완전히 같은 경로.
            // 낙관적 갱신·롤백·계측·시드 재구성이 갈라지면 안 된다.
            HypeIntentBridge.toggleHype = { trackId in
                guard let feed = feedList.first(where: { $0.trackId == trackId }) else { return }
                setHype(trackId: trackId, to: !feed.isHyped)
            }
            if isOnScreen {
                audio.updateWindow(feeds: feedList, current: currentIndex)
                logTrackViewed()   // 첫 트랙(index 0)은 onChange가 안 터지므로 여기서.
            }
        }
        .onDisappear { audio.stop() }          // 뷰 해제 시 정지
        // 탭 전환을 결정적으로 처리 — onAppear/onDisappear는 TabView에서 신뢰 불가.
        // 피드로 오면 현재 리스트로 재생 세팅, 떠나면 정지.
        .onChange(of: session.selectedTab) { _, tab in
            guard mode == .normal else { return }   // 픽 재생은 커버라 탭 전환과 무관하다.
            if tab == .feed {
                audio.updateWindow(feeds: feedList, current: currentIndex)
            } else {
                audio.stop()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            audio.updateWindow(feeds: feedList, current: currentIndex)
            prefetchArtwork(from: currentIndex)
            logTrackViewed()
        }
        // 백그라운드 일시정지는 없앴다 — 피드 디깅은 앱을 벗어나도 이어진다.
        // 미리듣기 정지와 체류 시간 표시는 컨트롤러가 didEnterBackground에서 직접 한다.
        // 다른 화면(마이페이지)에서 하입이 바뀌면 살아있는 피드 카드에도 반영.
        .onChange(of: session.hypeState) { _, state in
            for i in feedList.indices {
                if let hyped = state[feedList[i].trackId], feedList[i].isHyped != hyped {
                    feedList[i].isHyped = hyped
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: audio.isPaused)
        // 등장·퇴장 대칭 — 위에서 슬라이드로 들어오고, 나갈 때도 같은 길로 위로 물러난다.
        .animation(.easeInOut(duration: 0.4), value: toastMessage)
        .sheet(item: $detailTarget) { target in
            TrackDetailView(trackId: target.id)
        }
        .background { shareSheetHost }
        .overlay { pushOptInOverlay }
        // 좌표는 한 줄도 안 적는다. 대상 뷰가 올린 앵커를 여기 GeometryProxy가 자기 좌표계로 푼다.
        // **`ignoresSafeArea`는 GeometryReader에 건다** — 오버레이에만 걸면 원점이 화면 맨 위로
        // 올라가 구멍이 상단 인셋만큼 밀린다(픽 탭에서 밟았던 것과 같은 함정).
        .coachMarks(FeedCoach.steps, screen: "feed", isActive: showsCoach) { seenFeedCoach = true }
    }

    /// 특집 세트 완주 직후의 푸시 권한 안내. 바로 뒤에 iOS 권한 팝업이 같은 자리에 뜨므로
    /// 가운데 다이얼로그 형태를 유지한다 — 한 번의 대화가 두 단계로 이어지는 모양이 된다.
    /// 거절은 아무것도 호출하지 않아 .notDetermined가 남고, 하입 시점에 기회가 다시 온다.
    @ViewBuilder
    private var pushOptInOverlay: some View {
        // 픽 닫기 버튼. `.overlay`는 콘텐츠 전체 위에 얹혀 히트 테스트를 먼저 가져가므로,
        // 페이징 레이어의 탭 제스처와 경쟁하지 않는다(ZStack 형제로 두면 경쟁한다).
        if case .pick = mode {
            Button {
                audio.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            // overlay는 safe area 안쪽에 배치되므로 safeInsets를 또 더하면 두 번 밀린다.
            .padding(.leading, 12)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        if showPushOffer {
            PushOptInPopup(
                onAccept: {
                    PostHogSDK.shared.capture("push_optin_accepted",
                                              properties: ["source": "curation_done"])
                    session.requestPushAuthorization(source: "curation_done")
                    withAnimation(.easeIn(duration: 0.15)) { showPushOffer = false }
                },
                onDecline: {
                    PostHogSDK.shared.capture("push_optin_declined",
                                              properties: ["source": "curation_done"])
                    withAnimation(.easeIn(duration: 0.15)) { showPushOffer = false }
                }
            )
        }
    }

    /// 같은 뷰에 .sheet를 두 개(detailTarget과 함께) 달면 충돌하므로 별도 노드에 붙인다.
    /// 프로퍼티로 뺀 건 feed 체인이 길어져 타입체커가 시간 초과를 냈기 때문.
    private var shareSheetHost: some View {
        Color.clear.sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image, item.url])
        }
    }

    private struct DetailTarget: Identifiable { let id: Int }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let image: UIImage
        let url: String
    }

    /// 공유: dignify 아이덴티티 카드를 렌더해 시스템 공유 시트로 인스타그램 등 SNS에 보낸다.
    private func shareTrack(_ feed: Feed) {
        Task {
            guard let image = await ShareCard.render(
                trackName: feed.trackName,
                artistName: feed.artistName,
                genreName: feed.genreName,
                artworkURL: feed.artworkURL(size: 600)
            ) else { return }
            shareItem = ShareItem(image: image, url: feed.trackViewUrl)
        }
    }

    /// 접힌 상태(40pt 돋보기 버튼) → 탭하면 우측 기준으로 풀폭까지 펼쳐지며 포커스.
    /// 키보드가 내려가면(포커스 해제) 다시 버튼으로 축소. DSSearchBar를 그대로 재사용하고
    /// 프레임 폭만 애니메이션하며, 접힘 상태는 clip으로 돋보기 아이콘만 노출.
    /// 지금 무엇을 보고 있는지 알려주는 배지. 세트를 통째로 받았다는 감각은 이 배지와 곡 수만으로
    /// 낸다 — 리스트 화면을 만들면 "뭘 누를까" 결정 비용이 생겨 스와이프 경험과 충돌한다.
    /// 픽도 같은 자리를 쓴다(배지는 나가는 문이 아니라서 닫기 버튼은 따로 둔다).
    @ViewBuilder
    private var contextBadge: some View {
        switch mode {
        case .normal:
            if !isSearching, curationCount > 0, currentIndex < curationCount {
                badgePill("This week's set \(currentIndex + 1)/\(curationCount)")
            }
        case .pick(_, let nickname):
            badgePill("@\(nickname)'s pick \(currentIndex + 1)/\(feedList.count)")
        }
    }

    /// 성향 칩("Following your hypes" / "Random")이 지금 떠 있는가.
    /// **`contextBadge`의 세로 위치가 여기 걸려 있다** — 조건을 두 군데 따로 쓰면
    /// 한쪽만 고쳐졌을 때 두 알약이 같은 줄에 겹친다.
    private var showsModePill: Bool {
        mode == .normal && !isSearching && activeQuery.isEmpty
    }

    /// 성향 칩이 차지하는 세로 폭(12pt 텍스트 + 상하 5pt ≒ 25) + VStack 간격 8.
    /// 실측해서 맞추는 루프 대신 상수로 둔다 — 폰트가 고정 크기라 Dynamic Type에도 안 변한다.
    private static let modePillBand: CGFloat = 33

    /// 배지 상단. 기본값 +56은 검색 아이콘 행(top+8부터 40pt) 바로 아래인데,
    /// 성향 칩이 **정확히 같은 자리**에서 시작하므로 떠 있을 때는 그만큼 더 내린다.
    /// 픽 모드엔 검색 오버레이 자체가 없어 기본값을 그대로 쓴다.
    private var badgeTop: CGFloat {
        safeInsets.top + 56 + (showsModePill ? Self.modePillBand : 0)
    }

    private func badgePill(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
            .padding(.top, badgeTop)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    /// 픽 모드엔 검색이 없다. 닫기 버튼은 여기가 아니라 최상위 오버레이에 있다 —
    /// 이 자리(ZStack 형제)에 두면 아래 페이징 레이어의 탭 제스처가 먼저 먹어
    /// 첫 탭이 재생 토글로 새어 나간다.
    @ViewBuilder
    private func searchOverlay(fullWidth: CGFloat) -> some View {
        if mode == .normal {
            searchControls(fullWidth: fullWidth)
        }
    }

    private func searchControls(fullWidth: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer(minLength: 0)   // 접힘 시 버튼을 우측에 붙이고, 펼치면 풀폭으로 채운다.
                if isSearching {
                    // 펼침 상태에서만 DSSearchBar. 접힘 땐 전용 아이콘 버튼(아래)을 써서
                    // 40pt로 축소된 서치바에 아이콘이 클립되던 문제를 피한다.
                    DSSearchBar(
                        text: $searchText,
                        placeholder: "Search artists, tracks",
                        backgroundStyle: DSColor.surface,
                        borderStyle: DSColor.borderLight,
                        isFocused: $searchFocused,
                        onSubmit: { runSearch(searchText) }
                    )
                    .frame(width: fullWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // 성향 버튼이 검색 왼쪽에 선다. 피드 안에 두는 이유는 **효과가 보이는 자리가
                    // 여기뿐**이기 때문이다. 설정 화면에서 끄면 무엇이 달라졌는지 기억으로 비교해야 한다.
                    Button { toggleDiggingMode() } label: {
                        Image(systemName: session.diggingMode ? "sparkles" : "shuffle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.diggingMode ? "Following your hypes" : "Random")
                    Button(action: openSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")
                }
            }

            // 지금 피드가 무엇으로 만들어졌는지를 항상 띄운다. 껐을 때만 띄우면 켜진 상태가
            // 무명(無名)이라, 유저가 이 버튼이 무엇을 바꾸는지 눌러 보기 전엔 알 수 없다.
            // 문구는 설정 이름("켜짐/꺼짐")이 아니라 **지금 보고 있는 것**을 말한다.
            if showsModePill {
                Button { toggleDiggingMode() } label: {
                    HStack(spacing: 4) {
                        Text(session.diggingMode ? "Following your hypes" : "Random")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Switches between hype-based and random")
                .coachAnchor(.feedMode)
            }

            // 검색 결과 보는 중(모드 아님)엔 활성 쿼리 칩 표시. 탭하면 전체 피드로 복귀.
            if !activeQuery.isEmpty, !isSearching {
                Button(action: clearSearch) {
                    HStack(spacing: 4) {
                        Text(activeQuery)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DSColor.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearching)
    }

    /// 성향을 뒤집고 피드를 새로 받는다. 재요청은 `AppSession`이 `feedReloadToken`을 올려서
    /// 일으키므로, 위쪽 `onChange(of: session.feedReloadToken)`가 커서를 버리고 다시 받는다.
    /// 그 경로가 `audio.updateWindow`까지 하므로 여기서 오디오를 따로 건드리지 않는다.
    private func toggleDiggingMode() {
        let next = !session.diggingMode
        Task { await session.setDiggingMode(next, source: "feed") }
    }

    /// 검색 모드 하단 패널 — 최근 검색 + "'쿼리' 검색하기" 확정 행.
    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !recentSearches.isEmpty {
                Text("Recent searches")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.bottom, 4)
                ForEach(recentSearches, id: \.self) { term in
                    HStack(spacing: 12) {
                        Button { runSearch(term) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DSColor.textTertiary)
                                Text(term)
                                    .font(.system(size: 15))
                                    .foregroundStyle(DSColor.textPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { removeRecentSearch(term) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DSColor.textTertiary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                }
            }
            let typed = searchText.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty {
                Button { runSearch(typed) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                        Text("Search \"\(typed)\"")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(DSColor.brand)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        // 리스트 행(각자 버튼)을 제외한 여백 탭 → 검색 닫고 피드로 복귀.
        .contentShape(Rectangle())
        .onTapGesture { exitSearchMode() }
    }

    private func openSearch() {
        searchText = activeQuery          // 검색 재진입 시 기존 쿼리를 편집 가능하게.
        isSearching = true
        searchFocused = true
        audio.pauseCurrent()              // 검색 중엔 재생 정지.
    }

    /// 확정 없이 검색 모드만 빠져나온다(바깥 탭/뒤로). 결과·activeQuery는 유지.
    private func exitSearchMode() {
        isSearching = false
        searchFocused = false
        searchText = activeQuery
    }

    /// 검색 확정(Enter/최근검색 탭). 일반 피드를 스냅샷에 보관하고 결과로 교체한다.
    private func runSearch(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        addRecentSearch(query)
        if savedFeed == nil {             // 일반 피드에서 첫 진입 → 상태 보관.
            savedFeed = FeedSnapshot(list: feedList, index: currentIndex, cursor: nextCursor,
                                     curationCount: curationCount, curationSetKey: curationSetKey)
        }
        // 검색 결과엔 큐레이션 세트가 없다. 안 내리면 배지가 검색 결과에 그대로 남고,
        // 결과를 세트 길이만큼 넘기면 세트를 완주한 것으로 기록된다(logTrackViewed).
        curationCount = 0
        curationSetKey = ""
        isSearching = false
        searchFocused = false
        searchText = query
        activeQuery = query
        Task { await loadSearch(query) }
    }

    private func loadSearch(_ query: String) async {
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.search(query: query), as: API.FeedResponse.self)
            // 검색은 지금까지 이벤트가 하나도 없었다 — 몇 명이 쓰는지도, 뭘 찾는지도 못 봤다.
            // 검색 응답엔 장르 필터가 없어(searchFeedList) 취향 밖 청취의 유력한 출처다.
            // query를 담는 이유: 찾는데 없는 아티스트가 곧 다음 큐레이션·수집 후보다.
            PostHogSDK.shared.capture("search_performed", properties: [
                "query": query, "result_count": res.items.count,
            ])
            feedList = res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = res.hasMore ? res.nextCursor : nil
            // feedList를 교체하면 currentIndex는 0 그대로라 .onChange(of:currentIndex)가 안 터진다.
            // 오디오 윈도우를 직접 갱신하지 않으면 이전 피드 트랙 player가 남아 그게 재생됨.
            audio.updateWindow(feeds: feedList, current: currentIndex)
        } catch {
            loadFailed = true
            PostHogSDK.shared.capture("search_performed",
                                      properties: ["query": query, "failed": true])
        }
        isLoading = false
    }

    /// 검색 종료 → 보관해둔 일반 피드로 복원(재페치 없이).
    private func clearSearch() {
        isSearching = false
        searchFocused = false
        searchText = ""
        activeQuery = ""
        guard let saved = savedFeed else { return }
        feedList = saved.list
        currentIndex = saved.index
        nextCursor = saved.cursor
        curationCount = saved.curationCount
        curationSetKey = saved.curationSetKey
        savedFeed = nil
        audio.updateWindow(feeds: feedList, current: currentIndex)   // 원래 피드로 오디오 윈도우 복원
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.height
            }
            .onEnded { value in
                // 느리게 충분히 끌었거나(거리) 빠르게 튕겼으면(예측 착지점=속도 반영) 전환.
                // predictedEndTranslation은 손을 뗀 속도로 감속했을 때 도달할 위치라
                // 빠른 플릭은 짧게 움직여도 넘어가고, 느린 드래그는 거리 임계로 처리된다.
                let distance = value.translation.height
                let predicted = value.predictedEndTranslation.height
                // 감도 완화(쉽게 전환): 거리 10% / 속도예측 30%만 넘겨도 전환.
                if distance >= height * 0.10 || predicted >= height * 0.30 {
                    goingPrev(height: height)
                } else if distance <= height * -0.10 || predicted <= height * -0.30 {
                    goingNext(height: height)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        offset = 0
                    }
                }
            }
    }

    /// 더블탭(하입)에 우선권을 주고, 단일 탭(재생/일시정지 토글)은 더블탭이
    /// 성립 안 할 때만 발동. 그래서 단일 탭엔 두 번째 탭 대기 지연이 붙는다.
    private func tapGestures(height: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { triggerHype(at: $0.location) }
            .exclusively(before: SpatialTapGesture(count: 1).onEnded { value in
                handleSingleTap(at: value.location, height: height)
            })
    }

    /// 위아래 컨트롤 밴드 탭은 무시 — 버튼과 겹쳐 재생 토글이 오발동하는 걸 막는다.
    /// 아래는 정보/하입·상세·공유, 위는 검색 버튼(일반)과 닫기 버튼(픽).
    /// 제스처 레이어는 `simultaneousGesture`라 버튼 위에서도 같이 발동한다 —
    /// 그래서 첫 탭이 일시정지에 먹히고 버튼은 두 번째 탭에야 반응했다.
    private func handleSingleTap(at location: CGPoint, height: CGFloat) {
        let topBand = safeInsets.top + 56
        let bottomBand = safeInsets.bottom + 160
        guard location.y > topBand, location.y < height - bottomBand else { return }
        audio.toggleCurrentPlayback()
    }

    private func feedSlot(for feed: Feed, size: CGSize) -> some View {
        ZStack {
            backgroundArtwork(for: feed, size: size)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.4), location: 0.35),
                    .init(color: .black.opacity(0.85), location: 0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            TrackCardView(
                feed: feed,
                screenSize: size,
                safeAreaInsets: safeInsets,
                // 윈도에 카드가 셋 떠 있어서 전부 앵커를 달면 어느 카드를 뚫을지가 흔들린다.
                coachAnchors: feed.trackId == feedList.first?.trackId,
                onToggleHype: { toggleHype(for: feed) },
                onOpenDetail: { if requireAccount() { detailTarget = DetailTarget(id: feed.trackId) } },
                onShare: { shareTrack(feed) }
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 게스트가 계정 기능을 시도하면 로그인 시트를 띄우고 false를 반환한다.
    private func requireAccount() -> Bool {
        if session.authState == .guest {
            session.pendingSignIn = true
            return false
        }
        return true
    }

    /// 실제 청취(임계 시간 이상 재생)를 서버에 기록한다. fire-and-forget —
    /// 집계용이라 실패해도 재시도·UI 반응 없음.
    /// 게스트는 조용히 건너뛴다: /tracks/{id}/listen은 인증 엔드포인트라 401이고,
    /// 익명 기록은 유저별 리텐션 분석에 쓸 수 없다. 로그인 시트도 띄우면 안 되므로
    /// requireAccount()가 아니라 직접 가드한다.
    /// current 트랙이 실제로 바뀌었을 때만 노출 이벤트를 찍는다(스킵률의 분모).
    private func logTrackViewed() {
        guard feedList.indices.contains(currentIndex) else { return }
        let feed = feedList[currentIndex]
        guard feed.trackId != lastViewedTrackId else { return }
        lastViewedTrackId = feed.trackId
        // 세트를 지나 일반 피드로 넘어온 시점 = 완주. 다음 진입부터는 이 세트를 안 앞세운다.
        if curationCount > 0, currentIndex >= curationCount, !curationSetKey.isEmpty {
            // 이 블록은 세트 이후 모든 트랙에서 돌기 때문에, 기록 전 값으로 "방금 넘었는지"를
            // 가른다. 안 그러면 완주 후 스와이프할 때마다 권한 안내를 다시 검사하게 된다.
            let justFinished = seenCurationSet != curationSetKey
            seenCurationSet = curationSetKey
            if justFinished { offerPushIfNeeded() }
        }
        // genre는 로케일 무관한 영문명으로 보낸다 — 표시용 라벨을 보내면 Rock/록이
        // 서로 다른 값으로 집계돼 장르별 스킵률을 볼 수 없다.
        PostHogSDK.shared.capture("track_viewed", properties: [
            "track_id": feed.trackId, "artist": feed.artistName,
            "genre": feed.genreNameEn ?? feed.genreName ?? "",
            "source": source(for: feed.trackId),
            "background": audio.isBackground,
        ])
        session.sessionTrackViews += 1
        maybeAskReview()
    }

    /// 충분히 파고든 세션 중간에 딱 한 번 리뷰를 묻는다.
    ///
    /// 시점을 누적 카운트가 아니라 세션 뎁스로 잡은 이유: 실측에서 깊은 세션은 가입 당일에
    /// 나오고(중앙값 0.0일) 유저당 세션이 2.0회다. 며칠 뒤로 미루는 조건을 걸면 대상자가
    /// 통째로 잘린다. 지금 몰입해 있는 중이라는 게 우리가 가진 가장 좋은 신호다.
    ///
    /// ⚠️ 스토어 빌드에선 시스템이 실제로 시트를 띄웠는지 알 수 없다(365일 3회 제한·이미
    /// 평가한 유저). 그래도 플래그는 세운다 — 재시도할 방법이 없어서 확인 수단은 이벤트뿐이다.
    /// **TestFlight 빌드에선 호출해도 안 뜬다.** Xcode로 돌리는 빌드에선 제한 없이 떠서
    /// 동작 확인이 되는데, `didAskReview`가 남으니 다시 보려면 앱을 지웠다 깔아야 한다.
    private func maybeAskReview() {
        guard !didAskReview,
              session.sessionTrackViews >= Self.reviewViewThreshold,
              // 다른 요청이 떠 있는 순간은 피한다. 겹치면 둘 다 거절당한다.
              !showPushOffer, !session.pendingSignIn else { return }
        didAskReview = true   // 1초 안에 또 넘겨도 두 번 예약되지 않게 먼저 세운다.
        PostHogSDK.shared.capture("review_prompt_requested",
                                  properties: ["views": session.sessionTrackViews])
        // 스와이프가 끝난 뒤로 미룬다. 이 함수는 `.onChange(of: currentIndex)`에서 도는데,
        // 그 턴엔 카드 전환 애니메이션과 AVPlayer 윈도우 재구성이 같이 돈다. 거기에 StoreKit
        // 첫 호출(프레임워크 로드 + 시스템 통신)이 메인 스레드로 얹히면 전환이 눈에 띄게 끊긴다.
        Task {
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
    }

    /// 특집 세트 완주 직후 푸시 권한 안내를 띄운다. 알림이 알리는 대상이 방금 본 세트라
    /// 여기가 물어보기 가장 좋은 지점이다. 이미 답한 유저(.notDetermined 아님)에겐
    /// 보여줄 이유가 없으므로 그 경우엔 조용히 넘어간다.
    private func offerPushIfNeeded() {
        guard !didOfferPush, session.authState == .signedIn else { return }
        Task {
            guard await session.pushAuthorizationUndecided() else { return }
            PostHogSDK.shared.capture("push_optin_shown", properties: ["source": "curation_done"])
            didOfferPush = true
            withAnimation(.easeOut(duration: 0.2)) { showPushOffer = true }
        }
    }

    private func recordListen(trackId: Int) {
        // 스킵률 = 1 - track_listened/track_viewed. 게스트도 세야 하므로 서버 가드보다 먼저 찍는다.
        PostHogSDK.shared.capture("track_listened",
                                  properties: ["track_id": trackId, "source": source(for: trackId)])
        guard session.authState == .signedIn else { return }
        Task { try? await session.api.send(.listen(trackId: trackId)) }
    }

    /// 트랙을 떠날 때 실제 재생 시간을 남긴다. 청취 임계값(5초) 튜닝용 원시 분포 —
    /// track_listened는 임계값 통과 여부만 알려줘서 임계선을 어디로 옮길지 못 본다.
    private func logDwell(trackId: Int, seconds: Double) {
        PostHogSDK.shared.capture("track_dwell", properties: [
            "track_id": trackId, "seconds": (seconds * 10).rounded() / 10,
            "source": source(for: trackId),
            // 발사 시점이 아니라 체류 구간 전체를 본다 — 백그라운드에서 10분 듣고 복귀해
            // 스와이프하면 발사는 포그라운드에서 일어나기 때문이다.
            "background": audio.dwellHadBackground,
        ])
    }

    /// 이 트랙이 어느 경로로 화면에 떴는지. 검색은 장르 필터가 없어(searchFeedList)
    /// 취향 밖 곡이 섞이고, 큐레이션도 전 유저 동일이라 장르를 무시한다.
    /// 셋을 구분하지 않으면 "청취의 몇 %가 취향 밖인가"를 경로 탓으로 돌릴 수 없다.
    ///
    /// currentIndex가 아니라 trackId 위치로 판정한다 — dwell은 트랙을 떠난 뒤에 발사돼서
    /// currentIndex가 이미 다음 트랙으로 넘어가 있다.
    private func source(for trackId: Int) -> String {
        if !activeQuery.isEmpty { return "search" }
        guard let index = feedList.firstIndex(where: { $0.trackId == trackId }) else { return "feed" }
        return (curationCount > 0 && index < curationCount) ? "curation" : "feed"
    }

    /// play()부터 실제로 소리가 나기까지의 지연. 스와이프가 이보다 빨랐으면 발사되지 않으므로,
    /// **track_viewed는 있는데 이 이벤트가 없는 트랙 = 소리를 한 번도 못 들은 노출**이다.
    /// 그 비율이 청취율 저하를 재생 지연으로 설명할 수 있는지를 가른다.
    private func logPlaybackStart(trackId: Int, latency: Double) {
        PostHogSDK.shared.capture("track_playback_started", properties: [
            "track_id": trackId,
            "latency_ms": Int((latency * 1000).rounded()),
            "source": source(for: trackId),
            // 백그라운드엔 볼 화면이 없다. "무음 구간에 유저가 넘긴다"를 재는 지표라
            // 판독에서 걸러내야 한다.
            "background": audio.isBackground,
        ])
    }

    private func toggleHype(for feed: Feed) {
        guard requireAccount() else { return }
        guard let index = feedList.firstIndex(where: { $0.trackId == feed.trackId }) else { return }
        setHype(trackId: feed.trackId, to: !feedList[index].isHyped)
    }

    /// 하입 상태를 낙관적으로 갱신하고 서버와 동기화. 이미 목표 상태면 no-op.
    /// POST 409(이미 하입)·DELETE 404(기록 없음)는 목표와 일치하므로 성공 취급,
    /// 그 외 실패는 롤백한다. 페이징으로 인덱스가 밀릴 수 있어 매번 trackId로 재조회.
    private func setHype(trackId: Int, to target: Bool) {
        guard let index = feedList.firstIndex(where: { $0.trackId == trackId }),
              feedList[index].isHyped != target else { return }
        feedList[index].isHyped = target
        session.hypeState[trackId] = target       // 다른 화면(마이페이지)에 반영.
        audio.syncHype(trackId: trackId, isHyped: target)
        if target {
            PostHogSDK.shared.capture("track_hyped",
                                      properties: ["track_id": trackId, "source": source(for: trackId)])
        }
        Task {
            do {
                try await session.api.send(target ? .hype(trackId: trackId) : .unhype(trackId: trackId))
            } catch APIError.server(_, _, let status) where status == 409 || status == 404 {
                // 이미 목표 상태 — 롤백 불필요.
            } catch {
                if let i = feedList.firstIndex(where: { $0.trackId == trackId }) {
                    feedList[i].isHyped = !target
                }
                audio.syncHype(trackId: trackId, isHyped: !target)
                return   // 서버가 안 받았으니 시드도 안 바뀐다. 재구성할 이유가 없다.
            }
            session.hypeChangeToken += 1   // 디깅 프로필 통계가 다시 받아간다.
            if target { await refreshUpcoming() }
        }
    }

    /// 하입 직후 **아직 안 본 카드만** 새로 받아 갈아끼운다.
    ///
    /// 서버 피드는 최근 하입 곡과의 무드 유사도 순인데, 이걸 안 하면 방금 누른 하입이
    /// 다음 페이지부터 반영된다. 프리페치까지 감안하면 유저는 10~20곡 뒤에 변화를 만나고,
    /// 그때쯤이면 자기가 뭘 눌러서 그렇게 됐는지 모른다. 배지도 토스트도 없이
    /// 다음 카드가 실제로 달라지는 것으로 인과를 전달한다.
    ///
    /// **재생 중인 카드는 건드리지 않는다.** `currentIndex`까지는 그대로 두고 뒤만 교체하므로
    /// `updateWindow`가 현재 트랙의 플레이어를 재사용하고(`setCurrent`는 같은 id면 no-op)
    /// `current+1` 슬롯만 새로 만든다. 지금 듣는 곡이 끊기면 그건 반응이 아니라 사고다.
    ///
    /// 실패하거나 결과가 비면 아무것도 안 바꾼다 — 최악이 종전 동작(다음 페이지부터 반영)이다.
    private func refreshUpcoming() async {
        guard mode == .normal, activeQuery.isEmpty, !isPaging,
              feedList.indices.contains(currentIndex),
              // 큐레이션 세트를 지나기 전이면 손대지 않는다. 뒤를 갈아치우면 아직 안 들은
              // 세트 곡이 사라지고 완주 판정(curationCount)도 깨진다.
              currentIndex + 1 >= curationCount
        else { return }
        isPaging = true      // 같은 플래그로 페이지네이션과 상호 배제 — 서로 리스트를 덮지 않는다.
        defer { isPaging = false }

        // 커서를 안 보낸다 = 새 시드 기준 첫 페이지. 방금 하입한 곡 쪽으로 기운 순서가 여기 담긴다.
        guard let res = try? await session.api.send(.feed(), as: API.FeedResponse.self) else { return }
        let kept = Array(feedList.prefix(currentIndex + 1))
        let tail = FeedView.upcoming(after: kept, from: res.items.map(Feed.init))
        guard !tail.isEmpty else { return }

        feedList = kept + tail
        nextCursor = res.hasMore ? res.nextCursor : nil
        savedFeedCursor = nextCursor ?? ""
        // 뒤가 통째로 갈렸다. 새 곡들의 아트워크를 지금 위치 기준으로 다시 받는다.
        prefetchArtwork(from: currentIndex)
        // currentIndex가 안 바뀌므로 onChange(of: currentIndex)가 안 터진다. 다음 카드용
        // 플레이어를 여기서 직접 세우지 않으면 방금 버린 트랙이 그대로 대기하고 있다.
        if isOnScreen {
            audio.updateWindow(feeds: feedList, current: currentIndex)
        }
    }

    /// 새로 받은 페이지에서 **이번 세션에 이미 지나간 곡**을 걸러 꼬리로 쓸 목록을 만든다.
    /// 서버는 하입·큐레이션 곡만 제외할 뿐 "이 유저가 방금 스와이프해 넘긴 곡"은 모른다.
    /// 정렬이 바뀌면 앞서 본 곡이 다시 상위로 올라올 수 있어 여기서 막는다.
    static func upcoming(after kept: [Feed], from fresh: [Feed]) -> [Feed] {
        let seen = Set(kept.map(\.trackId))
        return fresh.filter { !seen.contains($0.trackId) }
    }

    private func backgroundArtwork(for feed: Feed, size: CGSize) -> some View {
        RemoteImage(url: URL(string: feed.artworkUrl)) { Color.black }
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.1)
        .blur(radius: 28)
        .brightness(-0.3)
        .saturation(1.4)
        .clipped()
    }

    private func triggerHype(at location: CGPoint) {
        guard requireAccount() else { return }
        // 탭 제스처는 하입을 켜기만 한다(false→true, true는 유지). 해제는 하입 버튼으로만.
        setHype(trackId: feedList[currentIndex].trackId, to: true)
        burstLocation = location
        burstConfetti = Self.makeConfetti()
        showsHypeBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            showsHypeBurst = false
        }
    }

    private static func makeConfetti(count: Int = 14) -> [ConfettiPiece] {
        (0..<count).map { _ in
            ConfettiPiece(
                color: [DSColor.brand, .yellow, .pink, .mint, .orange].randomElement()!,
                angle: .random(in: 0..<360),
                distance: .random(in: 40...90)
            )
        }
    }
    
    /// 잠금화면·이어폰의 다음/이전으로 트랙을 옮긴다. 화면이 없으니 애니메이션도 없다.
    ///
    /// **`.onChange(of: currentIndex)`에 기대지 않고 부수효과를 직접 부른다** — 백그라운드에선
    /// SwiftUI가 body를 다시 평가하지 않아 onChange가 안 터질 수 있다. 포그라운드에서
    /// onChange가 이어서 돌아도 셋 다 멱등이라(같은 trackId면 `setCurrent`는 no-op,
    /// 나머지 둘은 자체 dedup) 두 번 불려도 안전하다.
    private func remoteSeek(to index: Int) {
        guard feedList.indices.contains(index) else { return }
        currentIndex = index
        audio.updateWindow(feeds: feedList, current: index)
        prefetchArtwork(from: index)
        logTrackViewed()
        Task { await loadMoreIfNeeded() }
    }

    private func goingNext(height: CGFloat) {
        if currentIndex == feedList.count - 1 {
            // 픽은 곡 수가 정해져 있다. 마지막 곡에서 더 넘기려는 손짓은 "다 들었다"는 뜻이라
            // 첫 곡에서 위로 당길 때와 같이 닫는다(일반 피드는 무한이라 스냅백이 맞다).
            if case .pick = mode {
                audio.stop()
                dismiss()
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                offset = 0
            }
            return
        }
        // easeOut = fast-start → 손가락이 이미 움직인 속도를 이어받아 부드럽게 감속.
        withAnimation(.easeOut(duration: 0.26)) {
            offset = -height
        } completion: {
            currentIndex += 1
            offset = 0
            Task { await loadMoreIfNeeded() }
        }
    }

    private func goingPrev(height: CGFloat) {
        if currentIndex == 0 {
            // 픽은 커버라 첫 곡에서 더 당기면 "닫기"가 자연스럽다. 스냅백만 하면
            // 위로 튕겨나가려는 손짓이 아무 데도 안 닿는다.
            if case .pick = mode {
                audio.stop()
                dismiss()
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                offset = 0
            }
            return
        }
        withAnimation(.easeOut(duration: 0.26)) {
            offset = height
        } completion: {
            currentIndex -= 1
            offset = 0
        }
    }
    
    private struct TrackCardView: View {
        let feed: Feed
        let screenSize: CGSize
        let safeAreaInsets: EdgeInsets
        /// 코치마크가 가리킬 카드인가. 첫 카드에만 켠다.
        var coachAnchors: Bool = false
        let onToggleHype: () -> Void
        let onOpenDetail: () -> Void
        let onShare: () -> Void

        private var cardWidth: CGFloat { max(0, screenSize.width - 48) }

        var body: some View {
            VStack(spacing: 0) {
                Spacer()
                artwork
                Spacer()
                infoAndActions
                    .padding(.bottom, safeAreaInsets.bottom + 72)
            }
            .padding(.top, safeAreaInsets.top + 64)
            .frame(width: screenSize.width, height: screenSize.height)
        }

        private var artwork: some View {
            RemoteImage(url: feed.artworkURL(size: 600)) { DSShimmerView() }
                .scaledToFill()
                .frame(width: cardWidth, height: cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 16)
        }

        /// "이 트랙이 왜 떴는지" 힌트. 무드로 뽑힌 곡이면 그 근거가 된 **내 하입 곡**을,
        /// 아니면(콜드스타트·무작위·검색) 종전대로 장르명을 띄운다.
        ///
        /// **자리를 하나만 쓴다.** 둘을 같이 띄우면 근거가 있는 카드와 없는 카드가 한 화면에 섞여
        /// "얘만 왜 이유가 있지"가 된다. 한 칩이 있고 그 내용이 바뀌는 편이 설명 부채가 안 생긴다.
        /// DSGenreChip은 밝은 배경의 선택형 Button이라 어두운 카드엔 안 맞아 별도 스타일.
        @ViewBuilder
        private var genreLabel: some View {
            if let similar = feed.similarToTrackName {
                chip(Text("Feels like \(similar)"))
                    .accessibilityLabel("Because you hyped \(similar)")
            } else if let genreName = feed.genreName {
                chip(Text(verbatim: genreName))
                    .accessibilityLabel("Genre: \(genreName)")
            }
        }

        private func chip(_ label: Text) -> some View {
            label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.15), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
        }

        private var infoAndActions: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    genreLabel

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feed.trackName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(feed.artistName)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                HStack {
                    Button {
                        onToggleHype()
                    } label: {
                        Image("HypeIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                    .foregroundStyle(feed.isHyped ? DSColor.brand : DSColor.textTertiary)
                    .animation(.easeOut, value: feed.isHyped)
                    .accessibilityLabel(feed.isHyped ? "Unhype" : "Hype")
                    .coachAnchor(coachAnchors ? .hype : nil)

                    Spacer()
                    TrackActionButton(systemName: "opticaldisc", action: onOpenDetail)
                        .accessibilityLabel("Track details")
                    shareButton
                }
            }
            .padding(.horizontal, 20)
        }

        private var shareButton: some View {
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
    }

    /// subviews
    private struct TrackActionButton: View {
        let systemName: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }
    
    private struct HypeBurstView: View {
        let isOn: Bool
        let confetti: [ConfettiPiece]
        @State private var sparkProgress: CGFloat = 0
        @State private var iconScale: CGFloat = 0
        @State private var iconOpacity: CGFloat = 0

        var body: some View {
            ZStack {
                ForEach(confetti) { piece in
                    Capsule()
                        .fill(piece.color)
                        .frame(width: 3, height: 10)
                        .rotationEffect(.degrees(piece.angle))
                        .offset(
                            x: cos(piece.angle * .pi / 180) * piece.distance * sparkProgress,
                            y: sin(piece.angle * .pi / 180) * piece.distance * sparkProgress
                        )
                        .opacity(1 - sparkProgress)
                }

                Image("HypeIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(isOn ? DSColor.brand : DSColor.textTertiary)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) {
                    sparkProgress = 1
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    iconScale = 1
                    iconOpacity = 1
                }
                withAnimation(.easeIn(duration: 0.35).delay(0.3)) {
                    iconScale = 0.4
                    iconOpacity = 0
                }
            }
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    let angle: Double
    let distance: CGFloat
}

#Preview {
    FeedView()
        .environment(AppSession())
}

