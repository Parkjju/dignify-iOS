import SwiftUI
import PostHog

/// 픽 만들기 — 인스타그램 다중선택 갤러리 구조. 셀 탭이 선택 토글이고 배지는 체크가 아니라
/// **번호**(선택순 = 재생순). 소스는 탭/세그먼트가 아니라 **검색창 상태**로 갈린다:
/// 비어 있으면 내 크레이트, 검색을 확정하면 결과 그리드. 선택은 소스가 바뀌어도 유지된다.
struct PickComposeView: View {
    /// 게시 성공 후 목록을 다시 받게 한다.
    var onCreated: () async -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var crate: [PickTrack] = []
    @State private var crateCursor: Int?
    @State private var crateLoaded = false
    @State private var isPagingCrate = false

    @State private var searchText = ""
    /// 확정된 검색어. 비어 있으면 크레이트 그리드를 본다.
    @State private var activeQuery = ""
    @State private var results: [PickTrack] = []
    @State private var isSearching = false
    @State private var showRequestSheet = false

    /// 선택 순서가 곧 재생 순서라 Set이 아니라 배열.
    @State private var selected: [PickTrack] = []
    @State private var showTitleStep = false
    @State private var titleText = ""
    @State private var isPosting = false
    @State private var errorMessage: String?

    private let maxTracks = 30

#if DEBUG
    init(onCreated: @escaping () async -> Void) { self.onCreated = onCreated }

    /// 프리뷰 시드. crateLoaded를 세워두면 `.task`의 loadCrate()가 즉시 반환한다.
    init(previewCrate: [PickTrack]) {
        onCreated = {}
        _crate = State(initialValue: previewCrate)
        _crateLoaded = State(initialValue: true)
    }
#endif

    /// 검색에서 고른 비크레이트 곡은 크레이트 그리드 **앞에** 붙는다.
    /// 안 그러면 검색어를 지웠을 때 그 곡이 그리드에 자리가 없다. 이게 "통합 그리드"의 실체.
    private var crateGrid: [PickTrack] {
        let crateIds = Set(crate.map(\.trackId))
        return selected.filter { !crateIds.contains($0.trackId) } + crate
    }

    private var gridItems: [PickTrack] { activeQuery.isEmpty ? crateGrid : results }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DSSearchBar(text: $searchText,
                            placeholder: "Search artists, tracks, genres",
                            onSubmit: { runSearch() })
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                sourceHeader
                grid
                bottomBar
            }
            .background(DSColor.background)
            .navigationTitle("New pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(DSColor.textSecondary)
                }
            }
            .navigationDestination(isPresented: $showTitleStep) { titleStep }
            .sheet(isPresented: $showRequestSheet) { ArtistRequestSheet(prefill: activeQuery) }
            .task { await loadCrate() }
            // 검색어를 지우면 확정 상태도 풀려 크레이트 그리드로 돌아온다.
            .onChange(of: searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty { activeQuery = "" }
            }
        }
    }

    /// 지금 보고 있는 소스가 무엇인지 + 크레이트로 돌아가는 명시적 문. 검색창을 비우는 게
    /// 유일한 복귀 경로면 고른 곡들이 어디 갔는지 알 수 없다.
    private var sourceHeader: some View {
        HStack(spacing: 8) {
            Text(activeQuery.isEmpty ? "Your crate" : "Results for \"\(activeQuery)\"")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !activeQuery.isEmpty {
                Button {
                    searchText = ""      // onChange가 activeQuery까지 비운다.
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("Your crate").font(.system(size: 13, weight: .semibold))
                        if !selected.isEmpty {
                            Text(verbatim: "\(selected.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(DSColor.brand, in: Capsule())
                        }
                    }
                    .foregroundStyle(DSColor.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if isSearching || (!crateLoaded && activeQuery.isEmpty) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gridItems.isEmpty {
            emptyGrid
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 16) {
                    ForEach(gridItems) { track in
                        cell(track)
                            .onAppear {
                                guard activeQuery.isEmpty, track.trackId == crateGrid.last?.trackId else { return }
                                Task { await loadCrate(more: true) }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyGrid: some View {
        VStack(spacing: 12) {
            if activeQuery.isEmpty {
                Text("Nothing in your crate yet — search for tracks to add.")
            } else {
                Text("No results for \"\(activeQuery)\"")
                Button("Request \"\(activeQuery)\"") { showRequestSheet = true }
                    .foregroundStyle(DSColor.brand)
            }
        }
        .font(DSTypography.body)
        .foregroundStyle(DSColor.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cell(_ track: PickTrack) -> some View {
        let number = selected.firstIndex(of: track).map { $0 + 1 }
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: track.artworkUrl.itunesArtworkURL(size: 300)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSColor.surface
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) { badge(number) }
            .overlay {
                if number != nil {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DSColor.brand, lineWidth: 2.5)
                }
            }
            // 선택된 셀만 살짝 밀어 넣어 눌린 느낌을 준다.
            .scaleEffect(number == nil ? 1 : 0.96)
            .animation(.easeOut(duration: 0.15), value: number)

            Text(track.trackName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            Text(track.artistName)
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(track) }
        .accessibilityLabel(Text(verbatim: "\(track.trackName), \(track.artistName)"))
        .accessibilityAddTraits(number != nil ? .isSelected : [])
    }

    @ViewBuilder
    private func badge(_ number: Int?) -> some View {
        ZStack {
            Circle()
                .fill(number == nil ? Color.black.opacity(0.28) : DSColor.brand)
                .overlay { Circle().stroke(.white, lineWidth: 2) }
            if let number {
                Text(verbatim: "\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .padding(6)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage, !showTitleStep {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
            HStack(spacing: 14) {
                Text("\(selected.count) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected.isEmpty ? DSColor.textTertiary : DSColor.textPrimary)
                Spacer(minLength: 0)
                Button("Next") { errorMessage = nil; showTitleStep = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background(selected.isEmpty ? DSColor.border : DSColor.brand, in: Capsule())
                    .disabled(selected.isEmpty)
                    .animation(.easeOut(duration: 0.15), value: selected.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(DSColor.background)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    // MARK: - Title step

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardPreview
            titleField
            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
            Spacer()
            Button { post() } label: {
                Text(isPosting ? "Posting…" : "Post")
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isPosting)
        }
        .padding(20)
        .background(DSColor.background)
        .navigationTitle("Title")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 목록에 실제로 깔릴 모습을 그대로 보여준다 — 제목을 비우면 폴백이 뜬다는 걸
    /// 설명하는 대신 눈으로 보게 하는 게 짧다.
    private var cardPreview: some View {
        HStack(alignment: .top, spacing: 14) {
            PickThumbnailStack(urls: selected.prefix(3).map(\.artworkUrl), trackCount: selected.count)
            VStack(alignment: .leading, spacing: 6) {
                Text(titleText.isEmpty ? placeholderTitle : titleText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)
                Text("\(selected.count) tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var titleField: some View {
        HStack(spacing: 10) {
            // 플레이스홀더 = 비웠을 때 실제로 나올 제목. 그래서 별도 안내 문구가 필요 없다.
            TextField(placeholderTitle, text: $titleText)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textPrimary)
                .onChange(of: titleText) { _, text in
                    // Swift는 grapheme, Postgres varchar는 code point로 세므로 길이 합의는 포기하고
                    // 클라가 자르고 서버는 컬럼 상한만 지킨다.
                    if text.count > PickTitle.maxLength {
                        titleText = String(text.prefix(PickTitle.maxLength))
                    }
                }
            Text(verbatim: "\(titleText.count)/\(PickTitle.maxLength)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(titleText.count >= PickTitle.maxLength ? DSColor.brand : DSColor.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(DSColor.background, in: Capsule())
        .overlay { Capsule().stroke(DSColor.borderLight, lineWidth: 1.5) }
    }

    /// 선택한 곡들로 조립한 폴백 제목. 서버엔 저장하지 않는다.
    private var placeholderTitle: String {
        guard let first = selected.first else { return "" }
        return PickTitle.fallback(firstTrack: first.trackName,
                                  firstArtist: first.artistName,
                                  trackCount: selected.count,
                                  distinctArtistCount: Set(selected.map(\.artistName)).count)
    }

    // MARK: - Actions

    private func toggle(_ track: PickTrack) {
        if let index = selected.firstIndex(of: track) {
            selected.remove(at: index)   // 뒤 번호는 자동으로 당겨진다(재정렬 기능 없음).
        } else if selected.count < maxTracks {
            selected.append(track)
        } else {
            errorMessage = String(localized: "Up to \(maxTracks) tracks.")
        }
    }

    private func loadCrate(more: Bool = false) async {
        if more {
            guard let cursor = crateCursor, !isPagingCrate else { return }
            isPagingCrate = true
            defer { isPagingCrate = false }
            guard let res = try? await session.api.send(.myHypes(cursor: cursor), as: API.HypeListResponse.self)
            else { return }
            crate.append(contentsOf: res.items.map(PickTrack.init))
            crateCursor = res.nextCursor
            return
        }
        guard !crateLoaded else { return }
        let res = try? await session.api.send(.myHypes(), as: API.HypeListResponse.self)
        crate = res?.items.map(PickTrack.init) ?? []
        crateCursor = res?.nextCursor
        crateLoaded = true
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        activeQuery = query
        isSearching = true
        Task {
            let res = try? await session.api.send(.search(query: query), as: API.FeedResponse.self)
            results = res?.items.map(PickTrack.init) ?? []
            isSearching = false
        }
    }

    private func post() {
        guard !selected.isEmpty, !isPosting else { return }
        isPosting = true
        errorMessage = nil
        let title = PickTitle.normalized(titleText)
        // 크레이트에 없는 곡 = 검색으로 찾아 넣은 곡. 이 값이 0에 수렴하면 통합 그리드의
        // 검색 소스는 죽은 코드고, 높으면 검색 품질이 시급해진다.
        let crateIds = Set(crate.map(\.trackId))
        let fromSearch = selected.filter { !crateIds.contains($0.trackId) }.count
        Task {
            do {
                try await session.api.send(.createPick(title: title, trackIds: selected.map(\.trackId)))
                PostHogSDK.shared.capture("pick_created", properties: [
                    "track_count": selected.count,
                    "has_title": title != nil,
                    "from_search_count": fromSearch,
                ])
                await onCreated()
                dismiss()
            } catch APIError.server(_, let message, _) {
                errorMessage = message   // 금칙어 필터 등 서버 판정을 그대로 보여준다.
            } catch {
                errorMessage = String(localized: "Couldn't post. Try again.")
            }
            isPosting = false
        }
    }
}

/// 크레이트(하입)와 검색 결과가 같은 그리드에 섞이므로 두 wire 타입을 하나로 접는다.
struct PickTrack: Identifiable, Equatable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let artworkUrl: String

    var id: Int { trackId }

    init(_ item: API.HypeItem) {
        self.init(trackId: item.trackId, trackName: item.trackName,
                  artistName: item.artistName, artworkUrl: item.artworkUrl)
    }

    init(_ item: API.FeedItem) {
        self.init(trackId: item.trackId, trackName: item.trackName,
                  artistName: item.artistName, artworkUrl: item.artworkUrl)
    }

    init(trackId: Int, trackName: String, artistName: String, artworkUrl: String) {
        self.trackId = trackId
        self.trackName = trackName
        self.artistName = artistName
        self.artworkUrl = artworkUrl
    }
}

#if DEBUG
#Preview("Compose") {
    PickComposeView(previewCrate: PickPreview.tracks)
        .environment(AppSession())
}
#endif
