import SwiftUI

struct FeedView: View {
    @State private var feedList: [Feed] = Feed.mockFeed
    @State private var searchText: String = ""
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

                DSSearchBar(text: $searchText, placeholder: "아티스트, 트랙, 장르 검색")
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
            AsyncImage(url: .init(string: feed.artworkUrl)) { image in
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

