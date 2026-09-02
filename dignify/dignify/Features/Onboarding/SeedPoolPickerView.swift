import SwiftUI
import PostHog

/// 온보딩 시드 고르기 — 인기곡 풀에서 **직접 고른다.** 2지선다 3라운드를 대체했다.
///
/// 왜 바꿨나: 2지선다는 18곡 고정 풀에서 6곡만 보여주는데, 그 6곡이 취향에 안 맞으면
/// 시드를 고칠 경로가 5단계였고 실측상 죽어 있었다(라운드 완주 33명 → 시드 저장 4명).
/// 여기선 풀 전체가 보이고 검색까지 되므로 그 경로가 화면 안에 들어온다.
///
/// **셀 탭 = 프리뷰 재생, 선택은 오른쪽 위 배지다.** 두 동작을 한 탭에 겹치면 소리가 아니라
/// 아는 이름으로 고르게 되고, 그게 애초에 2지선다를 만든 이유였다(`15_personalization_ux.md` §4-3).
///
/// 신규 가입(온보딩)과 기존 유저(업데이트 후 1회)가 같은 화면을 쓴다. 다른 건 끝난 뒤 할 일뿐이라
/// `onFinish`로 넘긴다. 풀을 못 받는 경우는 이 뷰가 모른다 — 부르는 쪽이 `fetch`로 받아 보고 비면 안 띄운다.
struct SeedPoolPickerView: View {
    let pool: [API.FeedItem]

    /// 업데이트로 들어온 기존 유저인가. 자기가 요청한 적 없는 화면이 앱을 켜자마자 덮으므로
    /// "왜 지금 이게 떴는지" 한 줄이 더 붙는다.
    var isUpdate = false

    /// 다 고르고 버튼을 눌렀을 때. 인자는 실제로 고른 곡 수(건너뛰면 0).
    /// 던지면 화면에 에러가 남고 버튼은 다시 눌린다.
    var onFinish: (Int) async throws -> Void

    /// 서버 `SeedTracksUpdateRequest @Size(max)` · `MoodRecommender.SEEDS` · `SeedPickerView.limit`과
    /// 같아야 한다. 더 고르게 두면 시드가 잘려서 유저가 고른 곡 일부가 조용히 버려진다.
    private static let limit = 3

    @Environment(AppSession.self) private var appSession
    @State private var audio = FeedAudioController()

    /// 선택 순서를 그대로 배지 번호로 쓴다.
    @State private var selected: [API.FeedItem] = []
    @State private var searchText = ""
    /// 확정된 검색어. 비어 있으면 인기곡 풀을 본다.
    @State private var activeQuery = ""
    @State private var results: [API.FeedItem] = []
    @State private var isSearching = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// 상한을 넘겨 눌렀을 때만 잠깐 뜬다. 아무 일도 안 일어나면 고장으로 읽힌다.
    @State private var limitHint = false

    /// 검색에서 고른 곡은 풀에 없을 수 있다. 앞에 붙여두지 않으면 검색어를 지우는 순간
    /// 화면에서 사라져 어디로 갔는지 알 수 없다(픽 만들기와 같은 규칙).
    private var gridItems: [API.FeedItem] {
        guard activeQuery.isEmpty else { return results }
        let poolIds = Set(pool.map(\.trackId))
        return selected.filter { !poolIds.contains($0.trackId) } + pool
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DSSearchBar(text: $searchText,
                        placeholder: "Search artists, tracks",
                        onSubmit: { runSearch() })
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            grid
            bottomBar
        }
        .background(DSColor.background)
        .onAppear {
            // 이 화면이 소리를 내는 동안 아래 피드는 멈춰 있어야 한다.
            appSession.modalAudioActive = true
            PostHogSDK.shared.capture("onboarding_seed_shown", properties: [
                "pool_size": pool.count,
                "is_update": isUpdate,
            ])
        }
        .onDisappear {
            audio.stop()
            appSession.modalAudioActive = false
        }
        .onChange(of: searchText) { _, text in
            if text.trimmingCharacters(in: .whitespaces).isEmpty { activeQuery = "" }
        }
    }

    /// 부르는 쪽에서 미리 받아 둔다. 실패·빈 응답은 빈 배열로 뭉갠다 — 시드를 못 고르는 건
    /// 막을 일이 아니라 건너뛸 일이다(그 유저는 콜드스타트 피드가 받는다).
    static func fetch(_ session: AppSession) async -> [API.FeedItem] {
        do {
            let res = try await session.api.send(.onboardingSeedPool, as: API.SeedPoolResponse.self)
            #if DEBUG
            print("[seed-pool] 후보 \(res.items.count)곡")
            #endif
            return res.items
        } catch {
            // 실패해도 화면을 안 띄울 뿐이라 유저에겐 아무 말도 안 남는다. 그래서 여기 로그가 필요하다
            // — 서버가 안 줬는지, 디코딩이 깨졌는지가 콘솔에서만 갈린다.
            #if DEBUG
            print("[seed-pool] 풀을 못 받았다: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                // 아무것도 안 고르고 나갈 길. 없으면 취향에 맞는 곡이 하나도 없는 유저가 갇힌다.
                Button("Skip") { finish() }
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textTertiary)
                    .disabled(isSubmitting)
            }
            .frame(height: 44)

            Text("Which sound pulls you in?")
                .font(DSTypography.title1)
                .tracking(-0.48)
                .foregroundStyle(DSColor.textPrimary)
            // 한 줄만 둔다. 고르는 화면에서 규칙을 길게 설명하면 읽기 전에 넘긴다 —
            // 하입된다는 것도, 피드가 여기서 시작한다는 것도 고르고 나면 겪어서 알게 된다.
            Text("Tap to listen, then pick up to \(Self.limit).")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            // 업데이트 유저에겐 "왜 지금 이게 떴는지"만 한 줄 더 붙는다.
            if isUpdate {
                Text("Your feed follows the tracks you hype now.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gridItems.isEmpty {
            emptyGrid
        } else {
            ScrollView {
                if !activeQuery.isEmpty {
                    sourceHeader
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                          spacing: 16) {
                    ForEach(gridItems, id: \.trackId) { cell($0) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    /// 검색 중일 때만 뜬다. 풀을 보고 있을 땐 헤더 문구가 이미 무엇을 고르는 자리인지 말한다.
    private var sourceHeader: some View {
        HStack(spacing: 8) {
            Text("Results for \"\(activeQuery)\"")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                searchText = ""      // onChange가 activeQuery까지 비운다.
            } label: {
                Text("Popular now")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var emptyGrid: some View {
        Text("No results for \"\(activeQuery)\"")
            .font(DSTypography.body)
            .foregroundStyle(DSColor.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 아트워크 탭 = 재생, 오른쪽 위 배지 = 선택. 배지는 24pt인데 표적은 44pt다.
    private func cell(_ item: API.FeedItem) -> some View {
        let number = selected.firstIndex { $0.trackId == item.trackId }.map { $0 + 1 }
        let isPlaying = audio.activeTrackId == item.trackId && !audio.isPaused
        return VStack(alignment: .leading, spacing: 6) {
            artwork(item, number: number, isPlaying: isPlaying)
            Text(verbatim: item.trackName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            Text(verbatim: item.artistName)
                .font(.system(size: 10.5))
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.trackName), \(item.artistName)"))
        .accessibilityAddTraits(number != nil ? .isSelected : [])
    }

    private func artwork(_ item: API.FeedItem, number: Int?, isPlaying: Bool) -> some View {
        RemoteImage(url: item.artworkUrl.itunesArtworkURL(size: 300)) { DSColor.surface }
            .scaledToFill()
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // 재생 표시를 재생 중일 때만 띄우면 눌러서 들어보는 자리라는 걸 아무도 모른다.
            .overlay {
                ZStack {
                    Color.black.opacity(isPlaying ? 0.45 : 0.22)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(isPlaying ? 1 : 0.85))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            // 고른 것은 브랜드색으로 덮는다 — 3열에선 얇은 테두리가 멀리서 안 보인다.
            .overlay {
                if number != nil {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DSColor.brand.opacity(0.55))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { play(item) }
            .overlay(alignment: .topTrailing) { selectButton(item, number: number) }
            .animation(.easeOut(duration: 0.12), value: number)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
    }

    private func selectButton(_ item: API.FeedItem, number: Int?) -> some View {
        Button { toggle(item) } label: {
            Group {
                if let number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(DSColor.brand, in: Circle())
                } else {
                    Circle()
                        .fill(.black.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(number == nil ? Text("Select") : Text("Deselect"))
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if limitHint {
                Text("Up to \(Self.limit) tracks.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
                    .multilineTextAlignment(.center)
            }
            Button { finish() } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Start digging")
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(selected.isEmpty || isSubmitting)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(DSColor.background)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    // MARK: - Actions

    /// 같은 곡을 다시 누르면 일시정지라 이벤트는 **새 곡이 시작될 때만** 찍는다.
    private func play(_ item: API.FeedItem) {
        guard let url = URL(string: item.previewUrl) else { return }
        if audio.activeTrackId != item.trackId {
            PostHogSDK.shared.capture("onboarding_seed_previewed", properties: [
                "track_id": item.trackId,
                "from": activeQuery.isEmpty ? "pool" : "search",
            ])
        }
        audio.togglePreview(trackId: item.trackId, url: url)
    }

    private func toggle(_ item: API.FeedItem) {
        if let index = selected.firstIndex(where: { $0.trackId == item.trackId }) {
            selected.remove(at: index)
            return
        }
        guard selected.count < Self.limit else {
            withAnimation { limitHint = true }
            return
        }
        limitHint = false
        selected.append(item)
        // **검색에서 고른 비율이 이 개편의 핵심 질문이다** — 높으면 고정 풀이 취향을 못 덮고 있다는 뜻이다.
        PostHogSDK.shared.capture("onboarding_seed_selected", properties: [
            "track_id": item.trackId,
            "from": activeQuery.isEmpty ? "pool" : "search",
            "selected_count": selected.count,
        ])
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        activeQuery = query
        isSearching = true
        PostHogSDK.shared.capture("onboarding_seed_searched", properties: ["query": query])
        Task {
            let res = try? await appSession.api.send(.search(query: query), as: API.FeedResponse.self)
            // 그 사이 다른 검색어가 확정됐으면 이건 지난 결과다.
            guard query == activeQuery else { return }
            // ponytail: 첫 페이지만 쓴다 — 시드 3곡을 고르는 자리라 더 내려갈 이유가 없다.
            results = res?.items ?? []
            isSearching = false
        }
    }

    /// 고른 곡을 하입하고 끝낸다. **하입을 기다렸다가** 완료를 알린다 —
    /// 던지고 넘어가면 첫 피드 요청이 하입보다 먼저 도착해 무드 정렬이 안 걸린 피드를 본다.
    /// 실패한 하입은 시드가 하나 주는 것뿐이라 조용히 넘긴다.
    private func finish() {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        audio.stop()
        let picked = selected
        Task {
            defer { isSubmitting = false }
            for item in picked {
                appSession.hypeState[item.trackId] = true
                try? await appSession.api.send(.hype(trackId: item.trackId))
            }
            PostHogSDK.shared.capture("onboarding_seed_done", properties: ["count": picked.count])
            do {
                try await onFinish(picked.count)
            } catch {
                errorMessage = String(localized: "Couldn't save. Please try again.")
            }
        }
    }
}
