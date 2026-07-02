import SwiftUI

struct FeedView: View {
    @Environment(AppSession.self) private var session
    @State private var feedList: [Feed] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var nextCursor: String?
    @State private var isPaging = false
    @State private var searchText: String = ""
    @State private var isSearching = false
    @State private var searchFocused = false
    @State private var offset: CGFloat = 0
    @State private var currentIndex = 0
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
    private func loadInitialFeed(force: Bool = false) async {
        guard force || feedList.isEmpty else { return }
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.feed(), as: API.FeedResponse.self)
            feedList = res.items.map(Feed.init)
            currentIndex = 0
            nextCursor = res.hasMore ? res.nextCursor : nil
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
        guard let res = try? await session.api.send(.feed(cursor: cursor), as: API.FeedResponse.self)
        else { return }
        feedList.append(contentsOf: res.items.map(Feed.init))
        nextCursor = res.hasMore ? res.nextCursor : nil
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
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
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
                Text(loadFailed ? "피드를 불러오지 못했어요" : "표시할 트랙이 없어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                if loadFailed {
                    Button("다시 시도") { Task { await loadInitialFeed(force: true) } }
                        .foregroundStyle(DSColor.brand)
                }
            }
        }
        .ignoresSafeArea()
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
                .simultaneousGesture(doubleTapGesture())

                // 검색 중엔 피드 위에 투명 레이어를 깔아, 바깥(키보드 영역 밖) 탭으로
                // 포커스를 해제한다(→ closeSearch로 축소). 검색바보다 아래 z-order라 바 탭은 그대로.
                if isSearching {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { searchFocused = false }
                }

                searchOverlay(fullWidth: size.width - 32)
                    .padding(.horizontal, 16)
                    .padding(.top, safeInsets.top + 8)

                if showsHypeBurst {
                    HypeBurstView(isOn: feedList[currentIndex].isHyped, confetti: burstConfetti)
                        .position(burstLocation)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear(perform: resolveSafeInsets)
    }

    /// 접힌 상태(40pt 돋보기 버튼) → 탭하면 우측 기준으로 풀폭까지 펼쳐지며 포커스.
    /// 키보드가 내려가면(포커스 해제) 다시 버튼으로 축소. DSSearchBar를 그대로 재사용하고
    /// 프레임 폭만 애니메이션하며, 접힘 상태는 clip으로 돋보기 아이콘만 노출.
    private func searchOverlay(fullWidth: CGFloat) -> some View {
        HStack {
            Spacer(minLength: 0)   // 접힘 시 버튼을 우측에 붙이고, 펼치면 풀폭으로 채운다.
            DSSearchBar(
                // 접힘 상태: placeholder 비우고 배경/테두리도 투명 → 돋보기 아이콘만 남는다.
                text: $searchText,
                placeholder: isSearching ? "아티스트, 트랙, 장르 검색" : "",
                backgroundStyle: isSearching ? DSColor.surface : .clear,
                borderStyle: isSearching ? DSColor.borderLight : .clear,
                iconSize: isSearching ? 15 : 22,
                isFocused: $searchFocused
            )
            .frame(width: isSearching ? fullWidth : 40)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
            .allowsHitTesting(isSearching)   // 접힘 상태에선 TextField 대신 아래 버튼이 탭을 받음
            .overlay {
                if !isSearching {
                    Button(action: openSearch) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearching)
        .onChange(of: searchFocused) { _, focused in
            // 키보드 dismiss 시 축소 + 입력 초기화(검색 결과 배선은 이후 단계).
            if !focused { closeSearch() }
        }
    }

    private func openSearch() {
        isSearching = true
        searchFocused = true
    }

    private func closeSearch() {
        isSearching = false
        searchText = ""
    }

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height >= height * 0.22 {
                    goingPrev(height: height)
                } else if value.translation.height <= height * -0.22 {
                    goingNext(height: height)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        offset = 0
                    }
                }
            }
    }

    private func doubleTapGesture() -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                triggerHype(at: value.location)
            }
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
                safeAreaInsets: safeInsets
            ) {
                toggleHype(for: feed)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func toggleHype(for feed: Feed) {
        guard let index = feedList.firstIndex(where: { $0.trackId == feed.trackId }) else { return }
        feedList[index].isHyped.toggle()
    }

    private func backgroundArtwork(for feed: Feed, size: CGSize) -> some View {
        AsyncImage(url: .init(string: feed.artworkUrl)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color.black
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(1.1)
        .blur(radius: 28)
        .brightness(-0.3)
        .saturation(1.4)
        .clipped()
    }

    private func triggerHype(at location: CGPoint) {
        // 탭 제스처는 하입을 켜기만 한다(false→true, true는 유지). 해제는 하입 버튼으로만.
        feedList[currentIndex].isHyped = true
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
            withAnimation(.easeInOut(duration: 0.28)) {
                offset = 0
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            offset = -height
        } completion: {
            currentIndex += 1
            offset = 0
            Task { await loadMoreIfNeeded() }
        }
    }

    private func goingPrev(height: CGFloat) {
        if currentIndex == 0 {
            withAnimation(.easeInOut(duration: 0.28)) {
                offset = 0
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
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
            AsyncImage(url: feed.artworkURL(size: 600)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                DSShimmerView()
            }
            .frame(width: cardWidth, height: cardWidth)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 16)
        }

        private var infoAndActions: some View {
            VStack(alignment: .leading, spacing: 16) {
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

                    Spacer()
                    TrackActionButton(systemName: "opticaldisc")
                    TrackActionButton(systemName: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    /// subviews
    private struct TrackActionButton: View {
        let systemName: String

        var body: some View {
            Button {} label: {
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

