import SwiftUI

struct FeedView: View {
    @State private var currentIndex = 0
    @State private var searchText = ""
    @State private var activeQuery = ""
    @State private var isSearchMode = false
    @State private var recentSearches = ["indie pop", "shoegaze", "ambient"]
    @State private var hypedTrackIDs: Set<String> = []
    @State private var showsHypeBurst = false
    @GestureState private var dragOffset: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    private let tracks = MockFeedTrack.samples

    private var visibleTracks: [MockFeedTrack] {
        let query = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }

        return tracks.filter { track in
            track.title.localizedCaseInsensitiveContains(query)
                || track.artist.localizedCaseInsensitiveContains(query)
                || track.genre.localizedCaseInsensitiveContains(query)
        }
    }

    private var currentTrack: MockFeedTrack? {
        guard visibleTracks.indices.contains(currentIndex) else { return visibleTracks.first }
        return visibleTracks[currentIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if visibleTracks.isEmpty {
                    emptySearchView
                } else {
                    carousel(in: geometry)
                }

                if showsHypeBurst, let currentTrack {
                    HypeBurstView(isHyped: hypedTrackIDs.contains(currentTrack.id))
                        .transition(.scale.combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    searchOverlay
                        .padding(.top, max(geometry.safeAreaInsets.top, 54) + 8)
                        .padding(.horizontal, 16)

                    if isSearchMode {
                        searchPanel
                    }

                    Spacer()
                }

                if !isSearchMode, let currentTrack {
                    TrackInfoOverlay(
                        track: currentTrack,
                        isHyped: hypedTrackIDs.contains(currentTrack.id),
                        hypeCount: currentTrack.hypeCount + (hypedTrackIDs.contains(currentTrack.id) ? 1 : 0),
                        onHype: { toggleHype(for: currentTrack, showsBurst: true) }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isSearchMode, let currentTrack else { return }
                toggleHype(for: currentTrack, showsBurst: true)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: visibleTracks) { _, tracks in
            if currentIndex >= tracks.count {
                currentIndex = max(tracks.count - 1, 0)
            }
        }
    }

    private func carousel(in geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { index, track in
                if abs(index - currentIndex) <= 1 {
                    FeedCardView(track: track)
                        .offset(y: CGFloat(index - currentIndex) * geometry.size.height + dragOffset)
                }
            }
        }
        .clipped()
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: currentIndex)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 18)
                .updating($dragOffset) { value, state, _ in
                    guard !isSearchMode else { return }
                    state = value.translation.height
                }
                .onEnded { value in
                    guard !isSearchMode else { return }
                    updateIndex(after: value, viewportHeight: geometry.size.height)
                }
        )
    }

    private var searchOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("아티스트, 트랙, 장르 검색")
                        .foregroundStyle(.white.opacity(0.6))
                )
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onTapGesture {
                        openSearch()
                    }
                    .onSubmit {
                        confirmSearch(searchText)
                    }

                if isSearchMode || !activeQuery.isEmpty {
                    Button {
                        isSearchMode ? closeSearch() : clearSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 14)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            }

            if !activeQuery.isEmpty, !isSearchMode {
                Text(activeQuery)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DSColor.brand, in: Capsule())
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("최근 검색")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DSColor.textTertiary)
                .textCase(.uppercase)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(recentSearches, id: \.self) { search in
                Button {
                    confirmSearch(search)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DSColor.textTertiary.opacity(0.7))

                        Text(search)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0x374151))

                        Spacer()
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(DSColor.borderLight.opacity(0.7))
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    confirmSearch(searchText)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))

                        Text("\"\(searchText)\" 검색하기")
                            .font(.system(size: 14, weight: .medium))

                        Spacer()
                    }
                    .foregroundStyle(DSColor.brand)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.background)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeOut(duration: 0.2), value: isSearchMode)
    }

    private var emptySearchView: some View {
        VStack(spacing: 14) {
            Text("\"\(activeQuery)\"에 대한 결과가 없어요")
                .font(DSTypography.bodyMedium)
                .foregroundStyle(.white.opacity(0.55))

            Button {
                clearSearch()
            } label: {
                Text("전체 피드로 돌아가기")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchMode = true
        }
    }

    private func closeSearch() {
        searchText = activeQuery
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchMode = false
        }
    }

    private func confirmSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activeQuery = trimmed
        searchText = trimmed
        currentIndex = 0
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchMode = false
        }

        recentSearches = [trimmed] + recentSearches.filter { $0 != trimmed }
        recentSearches = Array(recentSearches.prefix(5))
    }

    private func clearSearch() {
        activeQuery = ""
        searchText = ""
        currentIndex = 0
        isSearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isSearchMode = false
        }
    }

    private func updateIndex(after value: DragGesture.Value, viewportHeight: CGFloat) {
        let threshold = viewportHeight * 0.18
        let predicted = value.predictedEndTranslation.height

        if (value.translation.height < -threshold || predicted < -threshold * 1.25),
           currentIndex < visibleTracks.count - 1 {
            currentIndex += 1
        } else if (value.translation.height > threshold || predicted > threshold * 1.25),
                  currentIndex > 0 {
            currentIndex -= 1
        }
    }

    private func toggleHype(for track: MockFeedTrack, showsBurst: Bool) {
        if hypedTrackIDs.contains(track.id) {
            hypedTrackIDs.remove(track.id)
        } else {
            hypedTrackIDs.insert(track.id)
        }

        guard showsBurst else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            showsHypeBurst = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            withAnimation(.easeIn(duration: 0.12)) {
                showsHypeBurst = false
            }
        }
    }
}

private struct FeedCardView: View {
    let track: MockFeedTrack

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RemoteArtworkView(url: track.artworkURL)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.12)
                    .blur(radius: 28)
                    .brightness(-0.28)
                    .saturation(1.35)
                    .clipped()

                Color.black.opacity(0.14)

                VStack {
                    Spacer(minLength: geometry.size.height * 0.14)

                    RemoteArtworkView(url: track.artworkURL)
                        .frame(width: max(geometry.size.width - 48, 220))
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 16)

                    Spacer(minLength: geometry.size.height * 0.3)
                }

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.4),
                        .black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * 0.45)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

private struct TrackInfoOverlay: View {
    let track: MockFeedTrack
    let isHyped: Bool
    let hypeCount: Int
    let onHype: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text("\(track.artist) · \(track.album)")
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.75))
            }

            HStack {
                Button(action: onHype) {
                    HStack(spacing: 7) {
                        HypeMark(isOn: isHyped, size: 28)

                        Text("\(hypeCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isHyped ? Color(hex: 0xA5B4FC) : .white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 18) {
                    TrackActionButton(systemName: "opticaldisc")
                    TrackActionButton(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

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
    let isHyped: Bool

    var body: some View {
        HypeMark(isOn: isHyped, size: 96)
            .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 8)
            .keyframeAnimator(initialValue: HypeBurstState()) { content, value in
                content
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0, duration: 0)
                    CubicKeyframe(1.3, duration: 0.2)
                    CubicKeyframe(1.0, duration: 0.18)
                    CubicKeyframe(0.0, duration: 0.27)
                }

                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0)
                    CubicKeyframe(1, duration: 0.16)
                    CubicKeyframe(1, duration: 0.2)
                    CubicKeyframe(0, duration: 0.29)
                }
            }
    }
}

private struct HypeBurstState {
    var scale: CGFloat = 0
    var opacity: CGFloat = 0
}

private struct HypeMark: View {
    let isOn: Bool
    let size: CGFloat

    var body: some View {
        Image("BrandMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(isOn ? DSColor.brand : DSColor.textTertiary)
            .frame(width: size, height: size)
            .accessibilityLabel(isOn ? "하입됨" : "하입")
    }
}

private struct RemoteArtworkView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0x20202A), Color(hex: 0x111118)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .clipped()
    }
}

private struct MockFeedTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let genre: String
    let artworkURL: URL
    let hypeCount: Int

    static let samples: [MockFeedTrack] = [
        MockFeedTrack(
            id: "17947",
            title: "So Easy (feat. Carl Carwell & Josie James)",
            artist: "101 North",
            album: "Forever Yours",
            genre: "R&B / Soul",
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/ae/58/87/ae588768-4b77-7b15-9347-9fe6b451f988/20UMGIM11769.rgb.jpg/600x600bb.jpg")!,
            hypeCount: 3
        ),
        MockFeedTrack(
            id: "18040",
            title: "Dance With Me (feat. Beanie Sigel) [Remix]",
            artist: "112",
            album: "The 2000's Party Mix, Vol. 3",
            genre: "R&B",
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/70/dc/aa/70dcaaf9-baa6-eaa3-a9e9-d278c0bc8ecd/247b964f-2b4f-4e7c-ae73-a55ac39e8c7c.jpg/600x600bb.jpg")!,
            hypeCount: 2
        ),
        MockFeedTrack(
            id: "12801",
            title: "Simpson Rd (feat. Camoflauge)",
            artist: "1247 GB",
            album: "Soulja Life Mentality",
            genre: "Hip-Hop",
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/e7/dc/64/e7dc64a0-e3d7-94aa-88cd-d18788c3e7f3/artwork.jpg/600x600bb.jpg")!,
            hypeCount: 3
        ),
        MockFeedTrack(
            id: "8572",
            title: "Partisan (Live)",
            artist: "16 Horsepower",
            album: "Live March 2001",
            genre: "Alternative",
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/4d/d9/e3/4dd9e36e-c68b-db5a-c21f-be2bea9d8c98/124379.jpg/600x600bb.jpg")!,
            hypeCount: 2
        ),
        MockFeedTrack(
            id: "14168",
            title: "Can't Let Go (A Jazz Tribute)",
            artist: "1895 & Calvin Richardson",
            album: "Juke Joint",
            genre: "Jazz",
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/40/ae/a6/40aea619-e56b-2ce8-5391-94fff224bae7/678394105917_cover.jpg/600x600bb.jpg")!,
            hypeCount: 4
        )
    ]
}

#Preview {
    MainTabView()
        .environment(AppSession())
}
