import SwiftUI
import PostHog

/// 픽 만들기 — 하입한 곡을 **날짜별 리스트**로 훑으며 고른다. 행 탭은 프리뷰 재생이고
/// 선택은 오른쪽 배지다(`PickTrackRow`). 배지는 체크가 아니라 **번호**(선택순 = 재생순).
///
/// 아트워크 그리드에서 리스트로 바꾼 이유: 그리드는 *이미 아는 곡*을 찾을 때 빠른데
/// 하입 목록은 대부분 기억나지 않는 곡이다. 날짜가 "그날 뭘 파고 있었는지"라는 맥락을 주고,
/// 재생이 회상을 마무리한다. 작성화면을 열고 85%가 아무것도 못 내고 나가던 구간이 여기다.
///
/// 소스는 탭/세그먼트가 아니라 **검색창 상태**로 갈린다: 비어 있으면 하입 목록,
/// 검색을 확정하면 결과 목록. 선택은 소스가 바뀌어도 유지된다.
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
    /// 확정된 검색어. 비어 있으면 하입 목록을 본다.
    @State private var activeQuery = ""
    @State private var results: [PickTrack] = []
    /// 검색 결과도 하입 목록과 똑같이 페이지가 있다(10개씩). nil이면 더 없음.
    @State private var searchCursor: String?
    @State private var isSearching = false
    @State private var isPagingSearch = false
    @State private var showRequestSheet = false

    /// 선택 순서가 곧 재생 순서라 Set이 아니라 배열.
    @State private var selected: [PickTrack] = []
    @State private var showTitleStep = false
    @State private var titleText = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    /// 제목 단계 미리보기의 `@닉네임`용. 요청이 실패해도 화면은 막지 않는다.
    @State private var myNickname = ""
    /// 한 번에 한 곡만 무는 단발 미리듣기. `onListen`을 안 붙였으므로 청취 집계에 안 들어간다 —
    /// 여긴 곡을 고르는 자리지 듣는 자리가 아니라서 피드 청취율을 오염시키면 안 된다.
    @State private var audio = FeedAudioController()
    /// 미리보기 카드가 `PickCard`를 그대로 쓰는데 zoom 전환 네임스페이스를 요구한다.
    /// 여기선 전환이 없어서 쓰이지 않는다.
    @Namespace private var previewNamespace

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

    /// 목록 한 덩어리. 날짜 그룹이면 제목이 있고, 검색 결과면 없다.
    private struct ListSection: Identifiable {
        let id: String
        let title: String?
        let tracks: [PickTrack]
    }

    /// 검색에서 고른 비하입 곡은 `hypedAt`이 없어서 날짜 그룹에 낄 자리가 없다.
    /// 맨 위에 따로 세워두지 않으면 검색어를 지우는 순간 목록에서 사라져 어디로 갔는지 알 수 없다.
    private var sections: [ListSection] {
        guard activeQuery.isEmpty else {
            return [ListSection(id: "results", title: nil, tracks: results)]
        }
        let crateIds = Set(crate.map(\.trackId))
        let added = selected.filter { !crateIds.contains($0.trackId) }
        let days = HypeGrouping.byDay(crate, date: { $0.hypedAt ?? .distantPast }).map {
            ListSection(id: "\($0.day.timeIntervalSince1970)",
                        title: $0.day.formatted(date: .long, time: .omitted),
                        tracks: $0.items)
        }
        guard !added.isEmpty else { return days }
        return [ListSection(id: "added",
                            title: String(localized: "Added from search"),
                            tracks: added)] + days
    }

    /// 페이지네이션 트리거가 물 마지막 행. 섹션이 아니라 **행** 기준이어야 한다 —
    /// 날짜 그룹 id는 startOfDay라 새 페이지가 전부 같은 날이면 값이 그대로다(1.0.9 버그와 같은 함정).
    private var listItems: [PickTrack] { sections.flatMap(\.tracks) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DSSearchBar(text: $searchText,
                            placeholder: "Search artists, tracks",
                            onSubmit: { runSearch() })
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                sourceHeader
                list
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
            // 만들기를 **연** 횟수. `pick_created`와 짝지어야 "만들다 말았다"가 보인다 —
            // 콜드스타트에서 유저 픽이 안 늘 때 곡 고르기에서 막히는지 게시에서 막히는지가 갈린다.
            .task {
                PostHogSDK.shared.capture("pick_compose_opened")
                await loadCrate()
            }
            // 검색어를 지우면 확정 상태도 풀려 하입 목록으로 돌아온다.
            .onChange(of: searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty { activeQuery = "" }
            }
            .onDisappear { audio.stop() }
        }
    }

    /// 지금 보고 있는 소스가 무엇인지 + 하입 목록으로 돌아가는 명시적 문. 검색창을 비우는 게
    /// 유일한 복귀 경로면 고른 곡들이 어디 갔는지 알 수 없다.
    private var sourceHeader: some View {
        HStack(spacing: 8) {
            Text(activeQuery.isEmpty ? "Your hypes" : "Results for \"\(activeQuery)\"")
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
                        Text("Your hypes").font(.system(size: 13, weight: .semibold))
                        if !selected.isEmpty {
                            Text("\(selected.count) selected")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DSColor.brand)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(DSColor.brandLight, in: Capsule())
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

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if isSearching || (!crateLoaded && activeQuery.isEmpty) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if listItems.isEmpty {
            emptyList
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DSColor.textTertiary)
                                .padding(.top, 10)
                        }
                        ForEach(section.tracks) { row($0) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func row(_ track: PickTrack) -> some View {
        PickTrackRow(track: track,
                     number: selected.firstIndex(of: track).map { $0 + 1 },
                     isPlaying: audio.activeTrackId == track.trackId && !audio.isPaused,
                     onPlay: { play(track) },
                     onToggle: { toggle(track) })
            // 마지막 행이 보이면 다음 페이지. 두 소스가 같은 목록을 쓰므로
            // 어느 쪽을 이어받을지는 `loadMore`가 검색어 상태로 가른다.
            .onAppear {
                guard track.trackId == listItems.last?.trackId else { return }
                Task { await loadMore() }
            }
    }

    private var emptyList: some View {
        VStack(spacing: 12) {
            if activeQuery.isEmpty {
                Text("No hyped tracks yet — search for tracks to add.")
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

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage, !showTitleStep {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
            HStack(spacing: 14) {
                // 0곡일 땐 개수가 아니라 무엇을 하라는 말이 필요하다.
                Text(selected.isEmpty ? "Select tracks to continue" : "\(selected.count) selected")
                    .font(.system(size: 14))
                    .foregroundStyle(selected.isEmpty ? DSColor.textTertiary : DSColor.textPrimary)
                Spacer(minLength: 0)
                Button("Next") { goToTitleStep() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected.isEmpty ? DSColor.textTertiary : .white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(selected.isEmpty ? DSColor.borderLight : DSColor.brand,
                                in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Preview")
                    cardPreview
                    HStack {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.textSecondary)
                        Spacer()
                        Text(verbatim: "\(titleText.count) / \(PickTitle.maxLength)")
                            .font(.system(size: 12))
                            .foregroundStyle(titleText.count >= PickTitle.maxLength
                                             ? DSColor.destructive : DSColor.textTertiary)
                            .monospacedDigit()
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    titleField
                    if let errorMessage {
                        Text(errorMessage)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.destructive)
                            .padding(.top, 8)
                    }
                    sectionLabel("\(selected.count) tracks").padding(.top, 24)
                    trackList
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            Button { post() } label: {
                Text(isPosting ? "Posting…" : "Post")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPosting)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DSColor.background)
            .overlay(alignment: .top) { Divider().opacity(0.6) }
        }
        .background(DSColor.background)
        .navigationTitle("Title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(DSColor.textTertiary)
            .padding(.bottom, 10)
    }

    /// 재생 순서를 번호로 확인하는 자리. 고르는 목록에선 번호 배지가 행 오른쪽 끝에 있어
    /// 순서를 위에서 아래로 훑기 어렵다.
    private var trackList: some View {
        VStack(spacing: 10) {
            ForEach(Array(selected.enumerated()), id: \.element.trackId) { index, track in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSColor.border)
                        .frame(width: 16)
                    AsyncImage(url: track.artworkUrl.itunesArtworkURL(size: 200)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        DSColor.surface
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.trackName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 12))
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 목록에 실제로 깔릴 모습. **목록 카드를 그대로 쓴다** — 손으로 다시 그리면 카드가
    /// 바뀔 때마다 여기가 조용히 낡는다(반응이 🔥 알약이 된 뒤에도 옛 `+` 원이 남아 있었고,
    /// 순서도 커버가 제목 위로 뒤집혀 있었다).
    ///
    /// **탭은 통째로 막는다** — 재생·반응·공유·`···`가 전부 여기선 뜻이 없다.
    private var cardPreview: some View {
        PickCard(pick: previewPick,
                 zoomNamespace: previewNamespace,
                 onPlay: {},
                 onReact: nil,
                 onMenu: {})
            .allowsHitTesting(false)
            // 카드가 좌우 16을 스스로 갖는데 이 화면도 16을 준다 — 되돌려야 목록에서와 같은 폭이 된다.
            .padding(.horizontal, -16)
    }

    /// 아직 서버에 없는 픽을 카드에 먹이기 위한 임시 값. `pickId`는 안 쓰인다(탭이 막혀 있다).
    /// `title`을 `normalized`로 넘기므로 비우면 카드가 폴백을 조립한다 — 목록에서 볼 모습 그대로다.
    private var previewPick: API.Pick {
        API.Pick(pickId: 0,
                 title: PickTitle.normalized(titleText),
                 nickname: myNickname,
                 isMine: true,
                 isOfficial: false,
                 createdAt: .now,
                 trackCount: selected.count,
                 distinctArtistCount: Set(selected.map(\.artistName)).count,
                 firstArtistName: selected.first?.artistName ?? "",
                 firstTrackName: selected.first?.trackName ?? "",
                 thumbnails: selected.prefix(3).map(\.artworkUrl),
                 reactions: [:],
                 myReaction: nil)
    }

    private var titleField: some View {
        // 플레이스홀더 = 비웠을 때 실제로 나올 제목. 그래서 별도 안내 문구가 필요 없다.
        TextField(placeholderTitle, text: $titleText)
            .font(.system(size: 15))
            .foregroundStyle(DSColor.textPrimary)
            .tint(DSColor.brand)
            .onChange(of: titleText) { _, text in
                // Swift는 grapheme, Postgres varchar는 code point로 세므로 길이 합의는 포기하고
                // 클라가 자르고 서버는 컬럼 상한만 지킨다.
                if text.count > PickTitle.maxLength {
                    titleText = String(text.prefix(PickTitle.maxLength))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
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

    /// 프리뷰는 한 번에 한 곡. 같은 곡을 다시 누르면 일시정지라 이벤트는 **새 곡이 시작될 때만** 찍는다 —
    /// 재생/정지를 반복해도 수치가 부풀지 않아야 "재생이 회상을 돕나"를 판정할 수 있다.
    private func play(_ track: PickTrack) {
        guard let url = URL(string: track.previewUrl) else { return }
        if audio.activeTrackId != track.trackId {
            PostHogSDK.shared.capture("pick_track_previewed",
                                      properties: ["from": activeQuery.isEmpty ? "crate" : "search"])
        }
        audio.togglePreview(trackId: track.trackId, url: url)
    }

    private func toggle(_ track: PickTrack) {
        if let index = selected.firstIndex(of: track) {
            selected.remove(at: index)   // 뒤 번호는 자동으로 당겨진다(재정렬 기능 없음).
        } else if selected.count < maxTracks {
            selected.append(track)
            // 작성화면 안이 통째로 무계측이라 85% 이탈이 곡 선택인지 제목 단계인지 못 갈랐다.
            // 이 이벤트가 "한 곡이라도 골랐다"의 하한선이다.
            PostHogSDK.shared.capture("pick_track_selected", properties: [
                "from": activeQuery.isEmpty ? "crate" : "search",
                "selected_count": selected.count,
            ])
        } else {
            errorMessage = String(localized: "Up to \(maxTracks) tracks.")
        }
    }

    /// 제목 단계로 넘어간 지점. `pick_track_selected`와 `pick_created` 사이의 마지막 관문이라
    /// 여기까지 온 사람이 몇인지가 이탈 구간을 가른다.
    private func goToTitleStep() {
        errorMessage = nil
        audio.stop()        // 다음 화면에서 소리만 남으면 어디서 나는지 알 수 없다.
        PostHogSDK.shared.capture("pick_title_step", properties: ["track_count": selected.count])
        showTitleStep = true
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
        // 미리보기 닉네임은 하입 목록과 같이 받아온다 — 나란히 쏴서 대기가 겹치게.
        async let profile = try? session.api.send(.myProfile, as: API.UserProfile.self)
        let res = try? await session.api.send(.myHypes(), as: API.HypeListResponse.self)
        myNickname = await profile?.nickname ?? ""
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
            // 그 사이 다른 검색어가 확정됐으면 이건 지난 결과다 — 늦게 도착한 쪽이 새 결과를
            // 덮어쓰면 검색창과 목록이 어긋난다. 다음 페이지 쪽과 같은 판정.
            guard query == activeQuery else { return }
            results = res?.items.map(PickTrack.init) ?? []
            searchCursor = res?.hasMore == true ? res?.nextCursor : nil
            isSearching = false
        }
    }

    /// 목록이 하입/검색 두 소스를 갈아끼우므로 다음 페이지 요청도 같이 갈린다.
    private func loadMore() async {
        if activeQuery.isEmpty {
            await loadCrate(more: true)
        } else {
            await loadMoreSearch()
        }
    }

    /// ponytail: 실패는 조용히 넘긴다 — 다음 스크롤에 다시 불린다(`loadCrate`와 같은 규칙).
    private func loadMoreSearch() async {
        guard let cursor = searchCursor, !isPagingSearch else { return }
        let query = activeQuery
        isPagingSearch = true
        defer { isPagingSearch = false }
        guard let res = try? await session.api.send(.search(query: query, cursor: cursor),
                                                   as: API.FeedResponse.self)
        else { return }
        // 페이지가 도는 사이 검색어가 바뀌었으면 이건 남의 결과다. 이어붙이면 다른 검색 결과가 섞인다.
        guard query == activeQuery else { return }
        results.append(contentsOf: res.items.map(PickTrack.init))
        searchCursor = res.hasMore ? res.nextCursor : nil
    }

    private func post() {
        guard !selected.isEmpty, !isPosting else { return }
        isPosting = true
        errorMessage = nil
        let title = PickTitle.normalized(titleText)
        // 하입 목록에 없는 곡 = 검색으로 찾아 넣은 곡. 이 값이 0에 수렴하면 통합 목록의
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
                // 마지막 단계까지 와서 못 낸 사람은 이탈로만 보이고 이유가 안 남는다.
                capturePostFailure("server")
            } catch {
                errorMessage = String(localized: "Couldn't post. Try again.")
                capturePostFailure("network")
            }
            isPosting = false
        }
    }

    private func capturePostFailure(_ reason: String) {
        PostHogSDK.shared.capture("pick_submit_failed", properties: [
            "reason": reason,
            "track_count": selected.count,
        ])
    }
}

#if DEBUG
#Preview("Compose") {
    PickComposeView(previewCrate: PickPreview.tracks)
        .environment(AppSession())
}
#endif
