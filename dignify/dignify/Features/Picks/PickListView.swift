import SwiftUI
import PostHog

/// 픽 지면. 남이 고른 곡 묶음이 최신순으로 깔리고, 카드를 누르면 그 자리에서 재생된다.
/// 게시판이 아니다 — 글이 없고 곡 묶음 + 이모지 반응이 전부.
struct PickListView: View {
    @Environment(AppSession.self) private var session

    @State private var picks: [API.Pick] = []
    @State private var nextCursor: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isPaging = false
    @State private var showCompose = false
    /// 재생 대상. fullScreenCover로 FeedView(.pick)를 덮어 목록 스크롤을 살려둔다.
    @State private var playing: API.Pick?
    @State private var reportTarget: API.Pick?
    @State private var blockTarget: API.Pick?
    @State private var toast: String?

    /// 차단·신고 숨김은 로컬 전용(§8). 서버는 차단을 모르고, 신고는 쌓기만 한다.
    @AppStorage(LocalModeration.blockedKey) private var blockedRaw = ""
    @AppStorage(LocalModeration.hiddenPicksKey) private var hiddenRaw = ""

#if DEBUG
    init() {}

    /// 프리뷰 시드. 목록이 비어있지 않으면 `.task`의 `load()`가 즉시 반환해 네트워크를 안 탄다.
    init(previewPicks: [API.Pick]) {
        _picks = State(initialValue: previewPicks)
        _isLoading = State(initialValue: false)
    }
#endif

    private var visiblePicks: [API.Pick] {
        let blocked = Set(LocalModeration.items(blockedRaw))
        let hidden = Set(LocalModeration.items(hiddenRaw))
        return picks.filter { !blocked.contains($0.nickname) && !hidden.contains(String($0.pickId)) }
    }

    var body: some View {
        content
            .navigationTitle("Picks")
            .background(DSColor.background)
            // 목록이 있을 때만. 빈 화면엔 이미 큰 CTA가 있어 두 개가 겹친다.
            .overlay(alignment: .bottom) { if !visiblePicks.isEmpty { composeButton } }
            .task { await load() }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showCompose) {
                PickComposeView { await load(force: true) }
            }
            .fullScreenCover(item: $playing) { pick in
                FeedView(mode: .pick(id: pick.pickId, nickname: pick.nickname))
            }
            .overlay(alignment: .top) { toastView }
            .confirmationDialog("Report this pick?", isPresented: reportBinding, presenting: reportTarget) { pick in
                Button("Inappropriate nickname") { report(pick, reason: "NICKNAME") }
                Button("Spam or promotion") { report(pick, reason: "SPAM") }
                Button("Something else") { report(pick, reason: "OTHER") }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Block @\(blockTarget?.nickname ?? "")", isPresented: blockBinding, presenting: blockTarget) { pick in
                Button("Block", role: .destructive) { block(pick) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their picks anymore. Undo it from My Page.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && picks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visiblePicks.isEmpty {
            emptyView
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(visiblePicks.enumerated()), id: \.element.pickId) { index, pick in
                    PickCard(
                        pick: pick,
                        onPlay: { open(pick, at: index) },
                        onReact: { react(pick, emoji: $0) },
                        onReport: { reportTarget = pick },
                        onBlock: { blockTarget = pick },
                        onDelete: { delete(pick) }
                    )
                    .onAppear {
                        guard pick.pickId == visiblePicks.last?.pickId else { return }
                        Task { await loadMore() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            // 떠 있는 만들기 버튼이 마지막 카드를 가리지 않게.
            .padding(.bottom, 88)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: loadFailed ? "exclamationmark.triangle.fill" : "square.stack.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DSColor.brand)
                .frame(width: 64, height: 64)
                .background(DSColor.brandLight, in: Circle())
                .padding(.bottom, 6)
            Text(loadFailed ? "Couldn't load" : "No picks yet")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            if loadFailed {
                Button("Try again") { Task { await load(force: true) } }
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.brand)
            } else {
                Text("Put a few tracks together and send them out.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                Button("Make a pick") { if requireAccount() { showCompose = true } }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.top, 14)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 만들기 진입점. 툴바 `+`보다 이쪽이 이 지면의 유일한 행동이라는 걸 분명히 한다.
    private var composeButton: some View {
        Button {
            if requireAccount() { showCompose = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("New pick")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(DSColor.brand, in: Capsule())
            .shadow(color: DSColor.brand.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.8), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Loading

    private func load(force: Bool = false) async {
        guard force || picks.isEmpty else { return }
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.picks(), as: API.PickListResponse.self)
            picks = res.items
            nextCursor = res.hasMore ? res.nextCursor : nil
        } catch {
            #if DEBUG
            // 백엔드에 /picks가 아직 없어서, 시뮬레이터에서 화면을 실제로 굴려보려면 목업이 필요하다.
            // 서버가 나오면 이 블록만 지운다(그때까지 DEBUG에선 loadFailed 상태를 볼 수 없다).
            picks = PickPreview.picks
            print("[Picks] 목록 요청 실패 → 목업으로 대체: \(error)")
            #else
            loadFailed = true
            #endif
        }
        isLoading = false
    }

    /// ponytail: 페이징 실패는 조용히 무시 — 다음 스크롤에 재시도된다.
    private func loadMore() async {
        guard let cursor = nextCursor, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        guard let res = try? await session.api.send(.picks(cursor: cursor), as: API.PickListResponse.self)
        else { return }
        picks.append(contentsOf: res.items)
        nextCursor = res.hasMore ? res.nextCursor : nil
    }

    // MARK: - Actions

    private func open(_ pick: API.Pick, at index: Int) {
        PostHogSDK.shared.capture("pick_opened", properties: ["position": index])
        playing = pick
    }

    /// 같은 이모지 재탭 = 해제, 다른 이모지 = 교체(서버 uq_pick_user가 1인 1개를 못박는다).
    /// 낙관적 반영 후 실패하면 그 카드만 되돌린다.
    private func react(_ pick: API.Pick, emoji: String) {
        guard requireAccount() else { return }
        guard let index = picks.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
        let previous = picks[index]
        let isUndo = previous.myReaction == emoji

        if let old = previous.myReaction {
            let left = (picks[index].reactions[old] ?? 1) - 1
            if left > 0 { picks[index].reactions[old] = left } else { picks[index].reactions[old] = nil }
        }
        if isUndo {
            picks[index].myReaction = nil
        } else {
            picks[index].reactions[emoji, default: 0] += 1
            picks[index].myReaction = emoji
        }

        PostHogSDK.shared.capture("pick_reacted", properties: [
            "emoji": emoji, "is_replace": previous.myReaction != nil && !isUndo,
        ])

        let endpoint = isUndo ? Endpoint.unreactPick(id: pick.pickId)
                              : .reactPick(id: pick.pickId, emoji: emoji)
        Task {
            do { try await session.api.send(endpoint) }
            catch {
                guard let i = picks.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
                picks[i] = previous
            }
        }
    }

    /// 신고한 카드는 즉시 로컬에서 숨긴다 — 운영자가 SQL로 처리하기 전 갭을 메우고,
    /// 안 사라지면 유저가 안 눌린 줄 안다.
    private func report(_ pick: API.Pick, reason: String) {
        PostHogSDK.shared.capture("pick_reported", properties: ["reason": reason])
        hiddenRaw = LocalModeration.adding(String(pick.pickId), to: hiddenRaw)
        showToast(String(localized: "Thanks — we'll take a look."))
        Task { try? await session.api.send(.reportPick(id: pick.pickId, reason: reason)) }
    }

    private func block(_ pick: API.Pick) {
        blockedRaw = LocalModeration.adding(pick.nickname, to: blockedRaw)
    }

    private func delete(_ pick: API.Pick) {
        picks.removeAll { $0.pickId == pick.pickId }
        Task {
            do { try await session.api.send(.deletePick(id: pick.pickId)) }
            catch { await load(force: true) }
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }

    /// 게스트는 읽기·재생만. 반응·게시는 로그인 시트로 보낸다(탭 자체는 안 막는다).
    private func requireAccount() -> Bool {
        if session.authState == .guest {
            session.pendingSignIn = true
            return false
        }
        return true
    }

    private var reportBinding: Binding<Bool> {
        Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } })
    }
    private var blockBinding: Binding<Bool> {
        Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } })
    }
}

// MARK: - Card

/// 한 카드 안에 재생(카드 탭)·반응(버튼)·오버플로 메뉴 세 인터랙션이 겹친다.
/// 제스처 우선순위로 풀지 않고 **구조로 가른다** — 재생 영역만 탭 제스처를 갖고,
/// 반응 행은 형제 노드, `···`는 오버레이라 애초에 겹치지 않는다.
/// 카드 전체를 Button으로 감싸면 반응 칩·Menu가 중첩돼 어느 쪽이 먹는지가 갈린다.
private struct PickCard: View {
    let pick: API.Pick
    let onPlay: () -> Void
    let onReact: (String) -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    private var title: String { pick.title ?? PickTitle.fallback(for: pick) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                PickThumbnailStack(urls: pick.thumbnails, trackCount: pick.trackCount)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.trailing, 24)   // 우상단 ··· 자리를 비워둔다.
                    // 닉네임·곡 수·시간을 한 줄로 묶어 카드가 덜 장황해진다. 닉네임만 무게를 준다.
                    HStack(spacing: 5) {
                        Text(verbatim: "@\(pick.nickname)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.brand)
                        Text(verbatim: "·").foregroundStyle(DSColor.border)
                        Text("\(pick.trackCount) tracks · \(pick.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 13))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // 없으면 썸네일과 제목 사이 여백·제목 오른쪽 빈 공간 탭이 죽는다.
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            reactionRow
        }
        .padding(16)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) { overflowMenu }
    }

    /// 높이 고정. 반응 0인 카드만 짧아지면 목록이 들쭉날쭉하고 첫 반응에 카드가 밀린다.
    /// placeholder를 **왼쪽 끝에 상시 노출**해서 카드마다 버튼 위치가 같다(슬랙은 뒤에 붙어 밀린다).
    private var reactionRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(PickReaction.all, id: \.self) { emoji in
                    Button { onReact(emoji) } label: {
                        Text("\(emoji)  ") + Text(PickReaction.label(emoji))
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(DSColor.background, in: Circle())
            }
            .accessibilityLabel("Add reaction")

            ForEach(PickReaction.all.filter { (pick.reactions[$0] ?? 0) > 0 }, id: \.self) { emoji in
                let mine = pick.myReaction == emoji
                Button { onReact(emoji) } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 11))
                        Text(verbatim: "\(pick.reactions[emoji] ?? 0)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mine ? .white : DSColor.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    // 내가 누른 칩만 브랜드로 채워 한눈에 갈린다(테두리 대비보다 강하다).
                    .background(mine ? DSColor.brand : DSColor.background, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PickReaction.label(emoji))
            }
            Spacer(minLength: 0)
        }
        // 반응은 카드의 주인공이 아니다 — 높이는 고정하되 시각 비중은 제목·아트워크 아래로 내린다.
        .frame(height: 26)
    }

    private var overflowMenu: some View {
        Menu {
            if pick.isMine {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            } else {
                Button(action: onReport) { Label("Report", systemImage: "flag") }
                Button(role: .destructive, action: onBlock) {
                    Label("Block @\(pick.nickname)", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: 32, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

/// 겹친 스택 썸네일. z-order 앞이 1번 곡이고, 뒤로 갈수록 작고 어둡다.
/// 4곡 이상이면 앞 3장 + `+N`.
struct PickThumbnailStack: View {
    let urls: [String]
    let trackCount: Int

    private let side: CGFloat = 96
    private let step: CGFloat = 9

    var body: some View {
        let shown = Array(urls.prefix(3))
        let extra = trackCount - shown.count
        ZStack(alignment: .leading) {
            // 뒤 장부터 그려야 1번 곡이 맨 위에 온다.
            ForEach(Array(shown.enumerated()).reversed(), id: \.offset) { index, url in
                // 아트워크 원본이 100×100이라 96pt@3x(288px)에선 뭉갠다 → 400으로 올려 받는다.
                AsyncImage(url: url.itunesArtworkURL(size: 400)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DSColor.surface
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                // 겹친 장끼리 경계가 안 보이면 그냥 어두운 사각형 하나로 읽힌다.
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white, lineWidth: index == 0 ? 0 : 2)
                }
                .brightness(index == 0 ? 0 : -0.12)
                .scaleEffect(pow(0.94, CGFloat(index)))
                .offset(x: step * CGFloat(index))
            }
        }
        .frame(width: side + step * 2, height: side, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(DSColor.brand, in: Capsule())
                    .overlay { Capsule().stroke(DSColor.surface, lineWidth: 2) }
                    .offset(x: 4, y: 4)
            }
        }
    }
}

#if DEBUG
#Preview("List") {
    NavigationStack {
        PickListView(previewPicks: PickPreview.picks)
    }
    .environment(AppSession())
}
#endif
