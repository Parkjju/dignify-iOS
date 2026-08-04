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
    /// 카드 아트워크 → 재생 화면 확대 전환용. iOS 18+에서만 실제로 쓰인다.
    @Namespace private var zoomNamespace

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
        // 제목은 네비바가 아니라 스크롤 콘텐츠 안에 직접 그린다(`titleHeader`).
        // 다크 지면에 흰 large title을 세우는 방법이 iOS 26엔 없다 — SwiftUI엔 색 API가 없고
        // (`toolbarColorScheme`은 좁아진 제목만 바꾼다), UIKit appearance는 navigationItem·
        // navigationBar 어디에 박아도 NavigationStack이 곧바로 자기 것으로 되돌린다
        // (전역 프록시·async 재적용까지 전부 밀렸다).
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.pickBackground)
            .toolbar(.hidden, for: .navigationBar)
            // 목록이 있을 때만. 빈 화면엔 이미 큰 CTA가 있어 두 개가 겹친다.
            .overlay(alignment: .bottom) { if !visiblePicks.isEmpty { composeButton } }
            .task { await load() }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showCompose) {
                PickComposeView { await load(force: true) }
            }
            .fullScreenCover(item: $playing) { pick in
                FeedView(mode: .pick(id: pick.pickId, nickname: pick.nickname))
                    .pickZoomTransition(id: pick.pickId, in: zoomNamespace)
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

    /// 시스템 large title 대체물. 스크롤 콘텐츠의 첫 요소라 스크롤에 그대로 밀려 올라간다.
    private var titleHeader: some View {
        Text("Picks")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && picks.isEmpty {
            // 스피너 대신 카드 골격. 도착 순간 레이아웃이 안 바뀌어 화면이 덜 튄다.
            // 제목까지 같이 그려야 로딩→목록 전환에 제목이 뒤늦게 나타나지 않는다.
            VStack(spacing: 12) {
                titleHeader
                ForEach(0..<3, id: \.self) { _ in PickSkeletonCard() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        } else if loadFailed && visiblePicks.isEmpty {
            errorView
        } else if visiblePicks.isEmpty {
            emptyView
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                titleHeader
                ForEach(Array(visiblePicks.enumerated()), id: \.element.pickId) { index, pick in
                    PickCard(
                        pick: pick,
                        zoomNamespace: zoomNamespace,
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // 떠 있는 만들기 버튼이 마지막 카드를 가리지 않게.
            .padding(.bottom, 88)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 0) {
            Text(verbatim: "🎵")
                .font(.system(size: 32))
                .frame(width: 72, height: 72)
                .background(DSColor.pickSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 20)
            Text("No picks yet")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text("Put a few tracks together and send them out.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .lineSpacing(3)
                .padding(.top, 8)
            Button("Make a pick") { if requireAccount() { showCompose = true } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
                .padding(.top, 24)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 16)
            Text("Couldn't load")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Please try again in a moment.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)
            Button { Task { await load(force: true) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    Text("Try again").font(.system(size: 14))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 20)
                .frame(height: 40)
                .overlay { Capsule().stroke(.white.opacity(0.25), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .multilineTextAlignment(.center)
        .padding(.bottom, 64)
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
            // 다크 지면에선 검은 알약이 배경에 묻는다 — 명암을 뒤집어야 토스트가 토스트로 보인다.
            Text(toast)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DSColor.pickBackground)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
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
            // 한계값 카드까지 붙여야 실기기에서 닉네임 20자·30곡·반응 5종을 눈으로 본다
            // (#Preview는 캔버스 전용이라 기기엔 안 뜬다).
            picks = PickPreview.picks + PickPreview.edgeCases
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
    let zoomNamespace: Namespace.ID
    let onPlay: () -> Void
    let onReact: (String) -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    @State private var showPicker = false

    private var hasReactions: Bool { pick.reactions.values.contains { $0 > 0 } }
    private var title: String { pick.title ?? PickTitle.fallback(for: pick) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 세로 구성 — 아트워크가 위, 글이 아래. 글이 아트워크 옆에 없으니 제목이 몇 줄이든
            // 위 요소가 밀리지 않는다. 제목 길이로 컬럼 높이를 맞출 이유 자체가 사라진다.
            VStack(alignment: .leading, spacing: 0) {
                PickThumbnailStack(urls: pick.thumbnails, trackCount: pick.trackCount)
                    // 곡 수에 따라 스택 폭이 달라진다(1곡 150 / 3곡 294). 왼쪽에 붙이면
                    // 1곡짜리 카드만 오른쪽이 휑해 보여서 가운데에 둔다.
                    .frame(maxWidth: .infinity)
                    .pickZoomSource(id: pick.pickId, in: zoomNamespace)
                    .padding(.bottom, 16)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // 닉네임은 왼쪽, 곡수·시간은 오른쪽 끝. 둘을 왼쪽에 몰아두면 카드 폭의
                // 절반이 남아 카드가 비어 보인다.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // 닉네임은 20자까지 올 수 있고 한글이면 훨씬 넓다. 줄이 넘치면
                    // 곡수·시간(짧고 사실 정보)을 지키고 닉네임을 자른다.
                    Text(verbatim: "@\(pick.nickname)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColor.pickAccent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text("\(pick.trackCount) tracks · \(pick.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 없으면 아트워크 오른쪽 여백이나 제목 옆 빈 공간 탭이 죽는다.
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            reactionRow
        }
        .padding(16)
        .background(DSColor.pickSurface, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
        .overlay(alignment: .topTrailing) { overflowMenu }
    }

    /// 높이 고정. 반응 0인 카드만 짧아지면 목록이 들쭉날쭉하고 첫 반응에 카드가 밀린다.
    /// placeholder를 **왼쪽 끝에 상시 노출**해서 카드마다 버튼 위치가 같다(슬랙은 뒤에 붙어 밀린다).
    private var reactionRow: some View {
        HStack(spacing: 6) {
            // 반응이 하나도 없으면 원 하나만 덩그러니 남아 행이 비어 보인다.
            // 그 자리에 할 말을 붙이면 빈 줄이 아니라 유도 문구가 된다(반응이 달리면 사라진다).
            Button { showPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        // 다크 카드 위에선 색을 얹는 대신 흰색을 옅게 태운다 — 카드가 어떤
                        // 밝기든 같은 만큼 떠 보이고, 서피스 색을 하나 더 정의할 필요도 없다.
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
                    if !hasReactions {
                        Text("Be the first to react")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add reaction")
            .popover(isPresented: $showPicker) { emojiPicker }

            ForEach(PickReaction.all.filter { (pick.reactions[$0] ?? 0) > 0 }, id: \.self) { emoji in
                let mine = pick.myReaction == emoji
                Button { onReact(emoji) } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 13))
                        Text(verbatim: "\(pick.reactions[emoji] ?? 0)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(mine ? DSColor.pickBackground : .white.opacity(0.75))
                            .lineLimit(1)
                    }
                    // 5종이 다 달리면 행이 빠듯하다. 압축을 허용하면 SwiftUI가 칩을 눌러
                    // 두 자리 숫자를 위아래로 쪼갠다 — 잘리는 게 낫지 접히면 못 읽는다.
                    // ponytail: 세 자리(100+)가 흔해지면 그때 가로 스크롤이나 상위 3종만.
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    // 내가 누른 칩만 브랜드로 채워 한눈에 갈린다(테두리 대비보다 강하다).
                    .background(mine ? DSColor.pickAccent : .white.opacity(0.08), in: Capsule())
                    .overlay { Capsule().stroke(mine ? .clear : .white.opacity(0.18), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PickReaction.label(emoji))
            }
            Spacer(minLength: 0)
        }
        // 반응 0이어도 행은 남는다 — 없애면 카드마다 높이가 달라지고 첫 반응에 카드가 밀린다.
        .frame(height: 30)
    }

    /// 5개를 한 번에 펼치는 팝오버. 아이폰에선 popover가 기본적으로 시트로 바뀌므로
    /// 말풍선으로 고정한다(StatBox의 안내 팝오버와 같은 처리).
    private var emojiPicker: some View {
        HStack(spacing: 2) {
            ForEach(PickReaction.all, id: \.self) { emoji in
                Button {
                    showPicker = false
                    onReact(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(pick.myReaction == emoji ? DSColor.pickAccent.opacity(0.3) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PickReaction.label(emoji))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .presentationCompactAdaptation(.popover)
        // 팝오버 배경은 시스템이 그린다 — 지면만 어둡게 하면 여기만 흰 말풍선으로 튄다.
        .preferredColorScheme(.dark)
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
            // 세로 구성에선 이 자리가 아트워크 위다. 반투명 알약을 깔아야 커버가 밝든 어둡든 보인다.
            // 오버레이는 카드 패딩 바깥에 얹히므로 간격도 여기서 직접 준다.
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.4), in: Circle())
                .contentShape(Circle())
                .padding(14)
        }
        .accessibilityLabel("More")
    }
}

/// 겹친 스택 썸네일. 1번 곡이 맨 앞·정위치고, 뒤 장은 오른쪽 아래로 밀리며 조금씩 눕는다.
/// 4곡 이상이면 앞 3장 + 맨 앞 장 위에 `+N`.
struct PickThumbnailStack: View {
    let urls: [String]
    let trackCount: Int

    /// 세로 카드에선 아트워크가 주인공이라 크게 잡고, 대신 겹침을 줄여 옆으로 넓게 편다.
    /// 3장이면 폭 230 — 카드 좌우에 여백이 남아 가운데 정렬이 눈에 보인다.
    private let side: CGFloat = 150
    private let shiftX: CGFloat = 40
    private let shiftY: CGFloat = 0
    /// 판이 커진 만큼 각도는 줄인다. 큰 커버가 많이 기울면 촌스럽다.
    private let tilt: Double = 4

    var body: some View {
        let shown = Array(urls.prefix(3))
        let extra = trackCount - shown.count
        ZStack(alignment: .topLeading) {
            // 뒤 장부터 그려야 1번 곡이 맨 위에 온다.
            ForEach(Array(shown.enumerated()).reversed(), id: \.offset) { index, url in
                // 진행도 0…1. 장이 2장이면 뒤 한 장이 끝까지 눕고, 3장이면 절반씩 나눠 눕는다.
                let t = shown.count > 1 ? CGFloat(index) / CGFloat(shown.count - 1) : 0
                // 아트워크 원본이 100×100이라 100pt@3x(300px)에선 뭉갠다 → 400으로 올려 받는다.
                AsyncImage(url: url.itunesArtworkURL(size: 400)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    // 이 스택은 다크(목록)와 라이트(만들기 시트) 양쪽에 쓰인다.
                    // 중립 회색이라야 어느 배경에서도 자리를 잡아준다.
                    Color.gray.opacity(0.25)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
                .overlay {
                    // 남은 곡 수는 맨 앞 장 한가운데. 스택 전체가 "몇 곡짜리 묶음"이라는
                    // 하나의 오브젝트로 읽힌다.
                    if index == 0, extra > 0 {
                        ZStack {
                            Color.black.opacity(0.5)
                            Text(verbatim: "+\(extra)")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
                    }
                }
                // 그림자가 깊이를 만든다 — 앞 장이 더 떠 보인다.
                .shadow(color: .black.opacity(index == 0 ? 0.18 : 0.09),
                        radius: index == 0 ? 9 : 4, y: index == 0 ? 6 : 2)
                .rotationEffect(.degrees(t * tilt))
                .offset(x: t * shiftX, y: t * shiftY)
            }
        }
        .frame(width: side + shiftX * CGFloat(max(0, shown.count - 1)),
               height: side + 10,
               alignment: .leading)
    }
}

/// 로딩 골격. 카드와 같은 치수라 데이터가 도착해도 레이아웃이 안 튄다.
private struct PickSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                bar(width: 294, height: 150, radius: DSRadius.large)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                bar(width: 190, height: 18, radius: 6)
                HStack {
                    bar(width: 80, height: 13, radius: 6)
                    Spacer(minLength: 0)
                    bar(width: 110, height: 12, radius: 6)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                bar(width: 30, height: 30, radius: 15)
                bar(width: 64, height: 30, radius: 15)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(DSColor.pickSurface, in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
    }

    private func bar(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.white.opacity(0.08))
            .frame(width: width, height: height)
    }
}

#if DEBUG
/// 일반 케이스 4장 + 한계값 3장을 한 캔버스에 이어 붙인다. 프리뷰를 나눠두면
/// 캔버스에서 한 번에 하나만 렌더돼 한계 케이스를 안 보고 지나친다.
#Preview("List") {
    NavigationStack {
        PickListView(previewPicks: PickPreview.picks + PickPreview.edgeCases)
    }
    .environment(AppSession())
}
#endif

// MARK: - Zoom transition (iOS 18+)

/// 카드 아트워크가 커지면서 재생 화면으로 이어지는 전환. 재생 화면은 검은 풀스크린이라
/// "확대 + 뒤가 어두워짐"이 전환 하나로 만들어진다. 17에선 기본 전환으로 조용히 폴백한다.
private extension View {
    @ViewBuilder
    func pickZoomSource(id: Int, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func pickZoomTransition(id: Int, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
