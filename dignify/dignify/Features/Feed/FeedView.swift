import SwiftUI

struct FeedView: View {
    @State private var feedList: [Feed] = Feed.mockFeed
    @State private var searchText: String = ""
    @State private var offset: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var currentIndex = 0
    @State private var showsHypeBurst = false
    @State private var burstLocation: CGPoint = .zero
    @State private var burstConfetti: [ConfettiPiece] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack {
                    if !feedList.isEmpty {
                        TrackCardView(feed: feedList[currentIndex], screenSize: geometry.size) {
                            feedList[currentIndex].isHyped.toggle()
                        }
                        .id(feedList[currentIndex].trackId)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            offset = value.translation.height
                        }
                        .onEnded { value in
                            if value.translation.height >= geometry.size.height * 0.22 {
                                goingPrev()
                            } else if value.translation.height <= geometry.size.height * -0.22 {
                                goingNext()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction:0.7)) {
                                    offset = 0
                                }
                            }
                        }
                )
                .gesture(
                    SpatialTapGesture(count: 2, coordinateSpace: .named("feed"))
                        .onEnded { value in
                            if !feedList.isEmpty {
                                triggerHype(at: value.location)
                            }
                        }
                )
                .offset(y: offset)


                DSSearchBar(text: $searchText, placeholder: "아티스트, 트랙, 장르 검색")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if showsHypeBurst {
                    HypeBurstView(isOn: feedList[currentIndex].isHyped, confetti: burstConfetti)
                        .position(burstLocation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "feed")
            .onAppear { containerHeight = geometry.size.height }
        }
    }
    
    private struct TrackCardView: View {
        let feed: Feed
        let screenSize: CGSize
        let onToggleHype: () -> Void

        private var cardWidth: CGFloat { screenSize.width - 48 }

        var body: some View {
            ZStack {
                backgroundArtwork

                VStack {
                    Spacer(minLength: screenSize.height * 0.08)
                    artwork
                    Spacer(minLength: screenSize.height * 0.3)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: screenSize.height * 0.45)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    infoAndActions
                }
            }
            .frame(width: screenSize.width, height: screenSize.height)
            .clipped()
        }

        private var backgroundArtwork: some View {
            AsyncImage(url: .init(string: feed.artworkUrl)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.black
            }
            .frame(width: screenSize.width, height: screenSize.height)
            .scaleEffect(1.1)
            .blur(radius: 28)
            .brightness(-0.3)
            .saturation(1.4)
            .clipped()
        }

        private var artwork: some View {
            AsyncImage(url: .init(string: feed.artworkUrl)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
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
            .padding(.bottom, 16)
        }
    }
    
    private func triggerHype(at location: CGPoint) {
        feedList[currentIndex].isHyped.toggle()
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
    
    private func goingNext() {
        if currentIndex == feedList.count - 1 {
            withAnimation(.easeInOut(duration: 0.28)) {
                offset = 0
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            offset = -containerHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            currentIndex += 1
            offset = 0
        }
    }
    
    private func goingPrev() {
        if currentIndex == 0 {
            withAnimation(.easeInOut(duration: 0.28)) {
                offset = 0
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            offset = containerHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            currentIndex -= 1
            offset = 0
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
}

