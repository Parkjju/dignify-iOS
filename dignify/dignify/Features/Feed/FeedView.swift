import SwiftUI
import PostHog

struct FeedView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var audio = FeedAudioController()
    @State private var feedList: [Feed] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var nextCursor: String?
    @State private var isPaging = false
    /// 앱 재구동 후 이어보기용으로 마지막 일반 피드 커서를 저장. 비면 처음부터(새 시드).
    @AppStorage("feedCursor") private var savedFeedCursor = ""
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
    @State private var currentIndex = 0
    /// track_viewed 중복 방지 — 탭 복귀 등으로 같은 트랙이 다시 current가 돼도 한 번만 찍는다.
    @State private var lastViewedTrackId: Int?
    @State private var detailTarget: DetailTarget?
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
            feedList = res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = res.hasMore ? res.nextCursor : nil
            savedFeedCursor = nextCursor ?? ""   // 소진되면 비워 다음 세션은 새 시드로.
            prefetchArtwork(feedList)
            // 소진 토스트는 스크롤로 실제 소진(페이징)했을 때만. 첫 로드/장르 교체 직후엔 안 띄운다.
            // 피드 탭일 때만 오디오를 갱신한다 — 다른 탭에서 장르 변경으로 재fetch된 경우
            // 여기서 재생하면 안 되고, 탭 복귀 시 onChange(selectedTab)가 새 리스트로 세팅한다.
            if session.selectedTab == .feed {
                audio.updateWindow(feeds: feedList, current: currentIndex)
            }
        } catch {
            loadFailed = true
        }
        isLoading = false
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
        prefetchArtwork(newFeeds)
        // 일반 피드일 때만 커서 저장(검색 커서는 세션 한정이라 저장 안 함).
        if activeQuery.isEmpty {
            savedFeedCursor = nextCursor ?? ""
            maybeShowGenreExhausted(res)
        }
    }

    /// 페이지의 아트워크(600px)를 URLCache에 미리 데운다. 완료를 기다리지 않고 발사만 —
    /// URLSession이 호스트당 동시성을 큐잉하고, 슬롯 렌더 시 AsyncImage가 캐시 히트로 즉시 뜬다.
    private func prefetchArtwork(_ feeds: [Feed]) {
        for feed in feeds {
            guard let url = feed.artworkURL(size: 600) else { continue }
            URLSession.shared.dataTask(with: url).resume()
        }
    }

    /// 로그인 유저(=장르 보유)의 피드가 장르 풀을 소진하면 세션당 한 번 토스트로 안내.
    /// 게스트는 장르가 없어 항상 exhausted라 제외한다.
    private func maybeShowGenreExhausted(_ res: API.FeedResponse) {
        guard res.genreExhausted == true, !genreExhaustedShown,
              session.authState == .signedIn else { return }
        genreExhaustedShown = true
        toastMessage = String(localized: "More beyond your genres")
        Task {
            try? await Task.sleep(for: .seconds(3))
            toastMessage = nil
        }
    }

    private struct FeedSnapshot { var list: [Feed]; var index: Int; var cursor: String? }

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

    var body: some View {
        content
            .task { await loadInitialFeed() }
            // 게스트로 본 피드는 하입 제외가 안 된 상태(userId 없이 요청). 로그인되면
            // 새 시드로 다시 받아 교체한다. FeedView가 이미 떠 있는 게스트→signedIn만 해당
            // (정상 로그인 진입은 마운트 전 전환이라 여기 안 걸리고 .task가 처리).
            .onChange(of: session.authState) { _, newState in
                guard newState == .signedIn else { return }
                activeQuery = ""
                savedFeed = nil
                savedFeedCursor = ""
                Task { await loadInitialFeed(force: true) }
            }
            // 마이페이지에서 장르를 바꾸면(다른 탭이라 FeedView는 떠 있음) 새 장르로 다시 받는다.
            .onChange(of: session.genreVersion) { _, _ in
                activeQuery = ""
                savedFeed = nil
                savedFeedCursor = ""
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
            if session.selectedTab == .feed {
                audio.updateWindow(feeds: feedList, current: currentIndex)
                logTrackViewed()   // 첫 트랙(index 0)은 onChange가 안 터지므로 여기서.
            }
        }
        .onDisappear { audio.stop() }          // 뷰 해제 시 정지
        // 탭 전환을 결정적으로 처리 — onAppear/onDisappear는 TabView에서 신뢰 불가.
        // 피드로 오면 현재 리스트로 재생 세팅, 떠나면 정지.
        .onChange(of: session.selectedTab) { _, tab in
            if tab == .feed {
                audio.updateWindow(feeds: feedList, current: currentIndex)
            } else {
                audio.stop()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            audio.updateWindow(feeds: feedList, current: currentIndex)
            logTrackViewed()
        }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? audio.resumeCurrent() : audio.pauseCurrent()
        }
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
    }

    private struct DetailTarget: Identifiable { let id: Int }

    /// 공유: activity 시트 대신 Apple Music URL만 클립보드에 복사하고 토스트 안내.
    private func shareTrack(_ feed: Feed) {
        UIPasteboard.general.string = feed.trackViewUrl
        toastMessage = String(localized: "Link copied")
        Task {
            try? await Task.sleep(for: .seconds(2))
            toastMessage = nil
        }
    }

    /// 접힌 상태(40pt 돋보기 버튼) → 탭하면 우측 기준으로 풀폭까지 펼쳐지며 포커스.
    /// 키보드가 내려가면(포커스 해제) 다시 버튼으로 축소. DSSearchBar를 그대로 재사용하고
    /// 프레임 폭만 애니메이션하며, 접힘 상태는 clip으로 돋보기 아이콘만 노출.
    private func searchOverlay(fullWidth: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer(minLength: 0)   // 접힘 시 버튼을 우측에 붙이고, 펼치면 풀폭으로 채운다.
                if isSearching {
                    // 펼침 상태에서만 DSSearchBar. 접힘 땐 전용 아이콘 버튼(아래)을 써서
                    // 40pt로 축소된 서치바에 아이콘이 클립되던 문제를 피한다.
                    DSSearchBar(
                        text: $searchText,
                        placeholder: "Search artists, tracks, genres",
                        backgroundStyle: DSColor.surface,
                        borderStyle: DSColor.borderLight,
                        isFocused: $searchFocused,
                        onSubmit: { runSearch(searchText) }
                    )
                    .frame(width: fullWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
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
            savedFeed = FeedSnapshot(list: feedList, index: currentIndex, cursor: nextCursor)
        }
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
            feedList = res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = res.hasMore ? res.nextCursor : nil
            // feedList를 교체하면 currentIndex는 0 그대로라 .onChange(of:currentIndex)가 안 터진다.
            // 오디오 윈도우를 직접 갱신하지 않으면 이전 피드 트랙 player가 남아 그게 재생됨.
            audio.updateWindow(feeds: feedList, current: currentIndex)
        } catch {
            loadFailed = true
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
                if distance >= height * 0.15 || predicted >= height * 0.45 {
                    goingPrev(height: height)
                } else if distance <= height * -0.15 || predicted <= height * -0.45 {
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

    /// 하단 정보/컨트롤 밴드(제목·하입·상세·공유) 탭은 무시 — 버튼과 겹쳐
    /// 재생 토글이 오발동하는 걸 막는다. 그 위 영역 탭만 재생/일시정지.
    private func handleSingleTap(at location: CGPoint, height: CGFloat) {
        let controlBand = safeInsets.bottom + 160
        guard location.y < height - controlBand else { return }
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
        PostHogSDK.shared.capture("track_viewed", properties: [
            "track_id": feed.trackId, "artist": feed.artistName, "genre": feed.genreName ?? "",
        ])
    }

    private func recordListen(trackId: Int) {
        // 스킵률 = 1 - track_listened/track_viewed. 게스트도 세야 하므로 서버 가드보다 먼저 찍는다.
        PostHogSDK.shared.capture("track_listened", properties: ["track_id": trackId])
        guard session.authState == .signedIn else { return }
        Task { try? await session.api.send(.listen(trackId: trackId)) }
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
        if target { PostHogSDK.shared.capture("track_hyped", properties: ["track_id": trackId]) }
        Task {
            do {
                try await session.api.send(target ? .hype(trackId: trackId) : .unhype(trackId: trackId))
            } catch APIError.server(_, _, let status) where status == 409 || status == 404 {
                // 이미 목표 상태 — 롤백 불필요.
            } catch {
                if let i = feedList.firstIndex(where: { $0.trackId == trackId }) {
                    feedList[i].isHyped = !target
                }
            }
        }
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
    
    private func goingNext(height: CGFloat) {
        if currentIndex == feedList.count - 1 {
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

        /// "이 트랙이 왜 떴는지" 힌트. 유저가 고른 장르 기준으로 피드가 구성되므로
        /// 장르명 자체가 선정 근거다. 서버가 현지화해 내려주며, 백엔드 배포 전이면 숨는다.
        /// DSGenreChip은 밝은 배경의 선택형 Button이라 어두운 카드엔 안 맞아 별도 스타일.
        @ViewBuilder
        private var genreLabel: some View {
            if let genreName = feed.genreName {
                Text(genreName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.15), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
                    .accessibilityLabel("Genre: \(genreName)")
            }
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

