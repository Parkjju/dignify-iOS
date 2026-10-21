import SwiftUI
import PostHog

/// 추천 기준 곡 고르기. 하입한 곡 중에서 최대 `limit`개를 고정하면, 서버가 최근 하입 대신
/// 그 곡들만 시드로 쓴다(`MoodRecommender.findSeeds`).
///
/// **아무것도 고르지 않은 상태가 기본이고 그게 정상이다.** 그때는 종전대로 최근 하입 세 곡이
/// 시드라, 이 화면에 한 번도 안 들어온 유저의 피드가 달라지지 않는다.
///
/// 목록은 최신 좋아요 순 세로 한 줄씩(seed_picker_opened 1.0). 행 탭 = 고르기/풀기 —
/// 이미 좋아요한 곡이라 들어 볼 이유가 적어서 미리듣기는 없다.
struct SeedPickerView: View {
    /// 서버 `SeedTracksUpdateRequest @Size(max)` 및 `MoodRecommender.SEEDS`와 같아야 한다.
    /// 더 고르게 두면 서버가 400으로 튕기거나 조용히 잘라낸다.
    private static let limit = 3

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 지금 고른 장르의 목록(nil = 전체).
    @State private var items: [API.HypeItem] = []
    /// 장르 칩 + 「좋아요한 곡 N」. 목록이 커서 페이지라 받은 개수로는 못 센다. 못 받으면 칩·줄을 숨긴다.
    @State private var genres: API.HypeGenresResponse?
    @State private var genreId: Int?
    /// 장르를 오가며 받은 곡 전부. 고른 곡이 지금 필터 밖에 있어도 트레이에 커버를 그린다.
    @State private var seen: [Int: API.HypeItem] = [:]
    @State private var didReportOpen = false
    @State private var selected: Set<Int> = []
    /// 저장 성공 여부를 판단할 기준. 서버에서 받은 그대로를 들고 있다가 비교한다.
    @State private var savedSelection: Set<Int> = []
    @State private var nextCursor: Int?
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var saveFailed = false
    @State private var showTip = false
    @State private var tipTask: Task<Void, Never>?
    /// 3곡 다 고른 뒤 안 고른 행을 누르면 뜬다.
    @State private var showLimit = false

    private var isFull: Bool { selected.count >= Self.limit }

    var body: some View {
        content
            .background(DSColor.background)
            .navigationTitle("Recommend from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 빈 화면엔 저장할 게 없다.
                if hasLikes {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save") { Task { await save() } }
                                .tint(DSColor.brand)
                                // 바꾼 게 없으면 누를 이유가 없다. 저장을 눌렀는데 아무 일도 안 일어나면
                                // 실패한 것처럼 보인다. 0곡 저장(= 최근 좋아요로 되돌리기)도 돼야 해서 개수로 막지 않는다.
                                .disabled(selected == savedSelection)
                        }
                    }
                }
            }
            .overlay {
                if showLimit {
                    DSNoticePopup(title: "Deselect one of your picks",
                                  message: "You can pick up to \(Self.limit).",
                                  onDismiss: { withAnimation { showLimit = false } })
                }
            }
            .task { await loadGenres() }
            // id가 바뀌면 이전 요청은 취소된다 — 칩을 빠르게 바꿔도 늦게 온 응답이 덮지 않는다.
            .task(id: genreId) { await loadList() }
    }

    /// 장르 필터 중엔 목록이 비어도(있을 수 없지만) 빈 화면이 아니다.
    private var hasLikes: Bool { !items.isEmpty || genreId != nil }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && loadFailed {
            Text("Couldn't load")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasLikes {
            emptyState
        } else {
            VStack(spacing: 0) {
                // 말풍선이 아래 목록 위로 내려와야 해서 앞에 그린다.
                header.zIndex(1)
                if let genres, !genres.genres.isEmpty { genreChips(genres.genres) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if let count = likeCount {
                            Text("Liked tracks \(count)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DSColor.textTertiary)
                                .padding(.bottom, 6)
                        }
                        ForEach(items) { row($0) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                // 인셋이라 목록 맨 아래에 트레이 높이만큼 여백이 생겨 마지막 줄이 안 가려진다.
                .safeAreaInset(edge: .bottom) { tray }
            }
            // 말풍선 바깥 탭 = 바로 닫기.
            // ponytail: 떠 있는 동안엔 이 덮개가 ⓘ도 덮어서 다시 누르면 2초 재시작 대신 닫힌다.
            .overlay {
                if showTip {
                    Color.clear.contentShape(Rectangle()).onTapGesture { hideTip(animated: false) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("Pick up to \(Self.limit) tracks.\nWe'll find music based on these.")
                    .font(DSTypography.title2)
                    .foregroundStyle(DSColor.textPrimary)
                Button(action: toggleTip) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(DSColor.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -13)   // 44 표적이 제목 줄 높이를 밀지 않게.
                // 말풍선은 2초라 VoiceOver가 못 읽는다. 같은 문장을 버튼 라벨에 둔다.
                .accessibilityLabel(Text(tipText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                if showTip {
                    tooltip
                        .alignmentGuide(.bottom) { $0[.top] - 8 }
                        .offset(x: 4)   // 헤더 여백 20 → 말풍선 오른쪽 끝은 화면 여백 16.
                        .transition(.opacity)
                }
            }
            // 꺼진 채로 들어올 수 있다. 고른 것이 지금 아무 데도 안 쓰인다는 걸 말해 주지 않으면
            // 저장하고 나서 피드가 그대로인 것을 고장으로 읽는다.
            if !session.diggingMode {
                Text("Turn on \"Follow my likes\" for these to take effect.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.brand)
            }
            if saveFailed {
                Text("Couldn't save. Please try again.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var likeCount: Int? {
        guard let genres else { return nil }
        guard let genreId else { return genres.total }
        return genres.genres.first { $0.genreId == genreId }?.count
    }

    /// 한 줄 가로 스크롤. 「전체」가 맨 앞. 고른 칩은 `textPrimary` — brand는 고른 곡 표시에 쓰여서 섞인다.
    private func genreChips(_ list: [API.HypeGenresResponse.Genre]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(Text("All"), id: nil, proxy: proxy)
                    ForEach(list) { chip(Text(verbatim: $0.genreName), id: $0.genreId, proxy: proxy) }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 4)
    }

    private func chip(_ label: Text, id: Int?, proxy: ScrollViewProxy) -> some View {
        let isOn = genreId == id
        return Button {
            guard !isOn else { return }
            genreId = id
            // 화면 밖 칩이면 보이게만 민다.
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id ?? -1, anchor: nil) }
        } label: {
            label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? .white : DSColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isOn ? DSColor.textPrimary : DSColor.surface, in: Capsule())
                .padding(.vertical, 5)   // 탭 영역 44
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(id ?? -1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var tipText: LocalizedStringKey {
        "Pick none and we'll find music based on your \(Self.limit) most recent likes."
    }

    private var tooltip: some View {
        Text(tipText)
            .font(DSTypography.caption)
            .lineSpacing(6)   // 줄높이 1.5
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(DSColor.textPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleTip() {
        tipTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showTip = true }
        tipTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hideTip(animated: true)
        }
    }

    private func hideTip(animated: Bool) {
        tipTask?.cancel()
        withAnimation(animated && !reduceMotion ? .easeIn(duration: 0.4) : nil) { showTip = false }
    }

    private func row(_ track: API.HypeItem) -> some View {
        let isOn = selected.contains(track.trackId)
        // 3곡이 차면 안 고른 행은 회색. 원은 남긴다 — 눌러서 「1개를 해제해 주세요」가 떠야 한다.
        let disabled = !isOn && isFull
        return HStack(spacing: 12) {
            RemoteImage(url: track.artworkUrl.itunesArtworkURL(size: 160)) { DSColor.surface }
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .saturation(disabled ? 0 : 1)
                .opacity(disabled ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(disabled ? DSColor.textTertiary : DSColor.textPrimary)
                Text(verbatim: track.genreName.map { "\(track.artistName) · \($0)" } ?? track.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textTertiary)
            }
            .lineLimit(1)
            .opacity(disabled ? 0.6 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            checkCircle(isOn: isOn)
                .opacity(disabled ? 0.6 : 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { toggle(track.trackId) }
        .animation(.easeOut(duration: 0.12), value: disabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .onAppear {
            if track.userHypeTrackId == items.last?.userHypeTrackId { Task { await loadMore() } }
        }
    }

    private func checkCircle(isOn: Bool) -> some View {
        ZStack {
            if isOn {
                Circle().fill(DSColor.brand)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(DSColor.textTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }

    /// 상한을 넘으면 가장 오래 고른 것을 밀어내지 않는다 — 방금 무엇이 빠졌는지 화면에서 안 보인다.
    /// 대신 왜 안 되는지 팝업으로 말한다.
    private func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
        } else if isFull {
            withAnimation { showLimit = true }
        } else {
            selected.insert(id)
        }
    }

    /// 탭바 위에 떠 있는 고른 곡 카드. 체크 표시 화면이라 순서 번호는 없다.
    /// 커버 탭도 ✕처럼 뺀다 — 세로 목록이라 그 곡을 찾아갈 이유가 적다.
    private var tray: some View {
        // Set이라 순서가 없다 — 최신 좋아요 먼저. 장르 필터가 바뀌어도 순서가 안 흔들리게 `seen`에서 뽑는다.
        // ponytail: 아직 안 받은 페이지에 고정된 곡은 커버를 모른다. 빈 커버로 두고, 페이지를 더 받으면 채워진다.
        let known = seen.values.filter { selected.contains($0.trackId) }
            .sorted { $0.userHypeTrackId > $1.userHypeTrackId }.map(\.trackId)
        let slots = (known + selected.subtracting(known).sorted()).map {
            SeedTray.Slot(id: $0, artworkUrl: seen[$0]?.artworkUrl ?? "")
        }
        return SeedTray(slots: slots, limit: Self.limit, numbered: false, hint: trayHint,
                        onTap: { selected.remove($0) },
                        onRemove: { selected.remove($0) })
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    private var trayHint: LocalizedStringKey {
        switch Self.limit - selected.count {
        case Self.limit: "Add up to \(Self.limit) tracks"
        case ...0: "All \(Self.limit) picked"
        case let left: "\(left) more to go"
        }
    }

    /// 좋아요가 하나도 없는 유저. 온보딩 곡은 이미 좋아요로 저장되므로 온보딩을 건너뛴 유저만 여기 온다.
    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark")
                .font(DSTypography.title1)
                .foregroundStyle(DSColor.brand)
                .frame(width: 56, height: 56)
                .background(DSColor.brandLight, in: Circle())
            Text("No liked tracks yet")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.top, 16)
            Text("Like tracks you dig in the feed")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .padding(.top, 6)
            Button {
                // 먼저 이 화면을 닫아 둔다 — 마이 탭으로 돌아왔을 때 빈 화면이 그대로 남아 있지 않게.
                dismiss()
                session.selectedTab = .feed
            } label: {
                Text("Find tracks")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadGenres() async {
        genres = try? await session.api.send(.myHypeGenres, as: API.HypeGenresResponse.self)
    }

    /// 첫 진입과 장르 변경. 고른 곡은 건드리지 않는다 — 장르를 바꿔도 트레이는 그대로다.
    private func loadList() async {
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.myHypes(genreId: genreId), as: API.HypeListResponse.self)
            guard !Task.isCancelled else { return }
            items = res.items
            nextCursor = res.nextCursor
            absorb(res.items)
            // 저장까지 간 비율을 보려면 분모가 필요하다. 목록을 못 받은 진입은 세지 않는다 —
            // 그때는 고를 수가 없어서 저장 안 한 게 유저의 선택이 아니다. 장르를 바꿀 때마다 세지 않는다.
            if !didReportOpen {
                didReportOpen = true
                PostHogSDK.shared.capture("seed_picker_opened",
                                          properties: ["pinned": savedSelection.count])
            }
        } catch {
            // 칩을 바꿔 취소된 것(URLSession 취소가 `APIError.transport`로 온다)은 실패가 아니다.
            // 다음 요청이 isLoading을 이어받는다.
            if Task.isCancelled { return }
            loadFailed = true
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        let genre = genreId
        guard let res = try? await session.api.send(.myHypes(cursor: cursor, genreId: genre), as: API.HypeListResponse.self),
              genre == genreId   // 받는 사이 칩이 바뀌었으면 버린다.
        else { return }
        items.append(contentsOf: res.items)
        nextCursor = res.nextCursor
        absorb(res.items)
    }

    /// 받은 곡을 `seen`에 쌓고, 처음 보는 고정 곡을 선택에 더한다. 유저가 아직 손대지 않은 것만 더한다 —
    /// 방금 해제한 곡이 페이지나 장르를 바꾸면서 되살아나면 안 된다. 화면에 없는 고정 곡도 저장 시 지워지지
    /// 않게 합집합으로 들고 간다.
    private func absorb(_ page: [API.HypeItem]) {
        for item in page {
            seen[item.trackId] = item
            if item.isSeed == true, !savedSelection.contains(item.trackId) {
                selected.insert(item.trackId)
                savedSelection.insert(item.trackId)
            }
        }
    }

    private func save() async {
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            try await session.api.send(.setSeedTracks(Array(selected)))
            savedSelection = selected
            // 0도 의미 있는 값이다 — 고정을 전부 풀고 최근 하입으로 되돌린 것.
            PostHogSDK.shared.capture("seed_saved", properties: ["count": selected.count])
            // 기준 곡이 바뀌면 정렬 기준 자체가 바뀐다. 들고 있던 커서로 이어 보면 옛 기준으로
            // 뽑힌 페이지가 계속 나와서, 방금 고른 게 반영이 안 된 것처럼 보인다.
            // 성향 토글과 같은 경로로 피드를 처음부터 다시 받게 한다.
            session.feedReloadToken += 1
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
