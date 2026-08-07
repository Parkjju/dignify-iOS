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
    @State private var menuTarget: API.Pick?
    @State private var menuStage: PickMenuSheet.Stage = .actions
    /// 시트에서 고른 동작. **시트가 닫힌 뒤에** 실행한다(`onDismiss`).
    @State private var pendingAction: PickMenuAction?
    @State private var blockTarget: API.Pick?
    /// 차단 확인창이 **닉네임 신고에서 이어진 것인지**. 문구가 갈린다.
    @State private var blockFromReport = false
    @State private var toast: String?
    /// 카드 아트워크 → 재생 화면 확대 전환용. iOS 18+에서만 실제로 쓰인다.
    @Namespace private var zoomNamespace

    /// 차단·신고 숨김은 로컬 전용(§8). 서버는 차단을 모르고, 신고는 쌓기만 한다.
    @AppStorage(LocalModeration.blockedKey) private var blockedRaw = ""
    @AppStorage(LocalModeration.hiddenPicksKey) private var hiddenRaw = ""
    /// 푸시 소프트 프롬프트. **피드와 같은 플래그를 공유한다** — 한 유저에게 한 번이면 충분하고,
    /// 이미 거절한 사람에게 맥락만 바꿔 또 묻는 건 스팸이다. 어느 쪽이 잘 먹는지는 `source`로 본다.
    @AppStorage("didOfferPush") private var didOfferPush = false
    @State private var showPushOffer = false
    /// 방금 픽을 올렸는가. 만들기 시트가 **완전히 닫힌 뒤** 물어보려고 잠깐 들고 있는다.
    @State private var justCreatedPick = false

    /// 픽 코치마크를 이미 봤는지. 1회성이라 로컬에만 둔다.
    /// **DEBUG에선 메모리에만 둔다** — `@AppStorage`면 한 번 보고 나서 다시 보려면 앱을 지워야 한다.
    /// 다시 켜면 초기화되므로 재빌드만으로 계속 확인할 수 있다.
#if DEBUG
    @State private var seenPicksCoach = false
#else
    @AppStorage("seenPicksCoach") private var seenPicksCoach = false
#endif

    /// 코치마크는 **가리킬 게 실제로 있을 때만** 뜬다. 카드가 없으면 뚫을 자리가 없고,
    /// 시트·재생 화면이 떠 있으면 그 위에 그려봐야 엉뚱한 자리를 가리킨다.
    /// 조건이 안 맞으면 본 것으로 치지 않고 다음 진입에 다시 시도한다.
    private var showsCoach: Bool {
        !seenPicksCoach && !visiblePicks.isEmpty && !isLoading
            && playing == nil && menuTarget == nil && blockTarget == nil && !showCompose
            && !showPushOffer
    }

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
        // 프로필에서 지운 픽은 여기 배열엔 아직 남아 있다. 목록을 다시 받지 않고 걸러낸다 —
        // 재요청하면 스크롤 위치와 이미 받아둔 페이지가 통째로 날아간다.
        return picks.filter {
            !blocked.contains($0.nickname)
                && !hidden.contains(String($0.pickId))
                && !session.deletedPickIds.contains($0.pickId)
        }
    }

    var body: some View {
        // 제목은 네비바가 아니라 스크롤 콘텐츠 안에 직접 그린다(`titleHeader`).
        // 다크 지면에 흰 large title을 세우는 방법이 iOS 26엔 없다 — SwiftUI엔 색 API가 없고
        // (`toolbarColorScheme`은 좁아진 제목만 바꾼다), UIKit appearance는 navigationItem·
        // navigationBar 어디에 박아도 NavigationStack이 곧바로 자기 것으로 되돌린다
        // (전역 프록시·async 재적용까지 전부 밀렸다).
        // **`content`를 그대로 두고 `.task`를 붙이면 안 된다.** 조건 분기라 스켈레톤→목록처럼
        // 분기가 바뀔 때마다 뷰 정체성이 갈리고, SwiftUI가 옛 분기의 `.task`를 취소한다 —
        // 진행 중이던 요청이 같이 죽어서 로그에 `/picks transport: 취소됨`만 남는다.
        // ZStack 하나로 정체성을 고정하면 분기가 바뀌어도 요청이 살아남는다.
        ZStack { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.pickBackground)
            .toolbar(.hidden, for: .navigationBar)
            // 목록이 있을 때만. 빈 화면엔 이미 큰 CTA가 있어 두 개가 겹친다.
            .overlay(alignment: .bottom) { if !visiblePicks.isEmpty { composeButton } }
            // 탭에 **도달한** 사람 수. 이게 없으면 `pick_opened`가 낮을 때 "와서 안 듣는 것"과
            // "탭에 아예 안 오는 것"을 못 가른다 — 콜드스타트에선 대응이 정반대다.
            // `.task`는 뷰 수명당 한 번이라 앱 실행당 첫 진입에서만 찍힌다.
            .task {
                PostHogSDK.shared.capture("pick_list_viewed")
                await load()
            }
            .refreshable { await load(force: true) }
            // 게시 직후가 아니라 **시트가 닫힌 뒤**에 물어본다. 시트 위에 팝업을 띄우면
            // 시트가 내려가면서 같이 사라진다(2026-07-21 중첩 제시 함정과 같은 부류).
            .sheet(isPresented: $showCompose, onDismiss: offerPushIfNeeded) {
                PickComposeView {
                    justCreatedPick = true
                    await load(force: true)
                }
            }
            .fullScreenCover(item: $playing) { pick in
                FeedView(mode: .pick(id: pick.pickId, nickname: pick.nickname))
                    .pickZoomTransition(id: pick.pickId, in: zoomNamespace)
            }
            .overlay(alignment: .top) { toastView }
            .overlay {
                if showPushOffer {
                    PushOptInPopup(
                        title: "Your pick is up",
                        message: "We'll let you know when someone drops a 🔥 on it.",
                        onAccept: {
                            PostHogSDK.shared.capture("push_optin_accepted",
                                                      properties: ["source": "pick_created"])
                            session.requestPushAuthorization(source: "pick_created")
                            withAnimation(.easeIn(duration: 0.15)) { showPushOffer = false }
                        },
                        onDecline: {
                            PostHogSDK.shared.capture("push_optin_declined",
                                                      properties: ["source": "pick_created"])
                            withAnimation(.easeIn(duration: 0.15)) { showPushOffer = false }
                        }
                    )
                }
            }
            // 1뎁스든 2뎁스든 **같은 시트 하나**를 닫았다 다시 연다(`menuStage`만 갈아끼운다).
            // `.sheet`을 두 개 달면 동시에 뜨지 않아도 서로를 잡아먹는다(2026-07-21에 밟음).
            // 고른 것은 `pendingAction`에 담아두고 **`onDismiss`에서** 실행한다 —
            // 닫힘이 끝난 뒤라 다음 시트도 alert도 안전하게 뜬다. 타이머로 때우지 않는다.
            .sheet(item: $menuTarget, onDismiss: runPendingAction) { pick in
                PickMenuSheet(pick: pick, stage: menuStage) { action in
                    pendingAction = action
                    menuTarget = nil
                }
            }
            // 메뉴에서 온 차단과 닉네임 신고 뒤 이어지는 제안은 **문구가 다르다.**
            // 후자는 유저가 차단을 고른 적이 없어서, 왜 이게 떴는지부터 설명해야 한다.
            .alert(blockAlertTitle, isPresented: blockBinding, presenting: blockTarget) { pick in
                Button("Block", role: .destructive) { block(pick) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(blockAlertMessage)
            }
            // 코치마크는 **맨 바깥**에 올린다. 여기까지 와야 떠 있는 만들기 버튼(`.overlay`)의
            // 앵커도 같이 읽히고, 오버레이가 그 버튼 위에 덮인다.
            // 좌표는 한 줄도 안 적는다 — 대상 뷰가 올린 `Anchor<CGRect>`를 여기 `GeometryProxy`가
            // 자기 좌표계로 풀어주므로 기기 크기·Dynamic Type이 달라져도 구멍이 따라간다.
            .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if showsCoach {
                        CoachMarkOverlay(steps: PicksCoach.steps,
                                         anchors: anchors,
                                         proxy: proxy) { seenPicksCoach = true }
                    }
                }
                // **`GeometryReader`에 걸어야** 어둠이 화면 끝까지 가면서 `proxy` 좌표계도
                // 같이 넓어진다. 안쪽 오버레이에만 걸면 좌표계가 안 따라와 구멍과 카드가
                // 상단 인셋만큼 위로 밀린다.
                .ignoresSafeArea()
            }
    }

    /// 시스템 large title 대체물. 스크롤 콘텐츠의 첫 요소라 스크롤에 그대로 밀려 올라간다.
    private var titleHeader: some View {
        Text("Picks")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 카드가 좌우 여백을 직접 갖는 구조라 제목도 같은 16pt를 직접 챙긴다.
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && picks.isEmpty {
            // 스피너 대신 카드 골격. 도착 순간 레이아웃이 안 바뀌어 화면이 덜 튄다.
            // 제목까지 같이 그려야 로딩→목록 전환에 제목이 뒤늦게 나타나지 않는다.
            VStack(spacing: 14) {
                titleHeader
                ForEach(0..<3, id: \.self) { _ in PickSkeletonCard() }
                Spacer()
            }
            .padding(.top, 12)
        } else if loadFailed && visiblePicks.isEmpty {
            pullable { errorView }
        } else if visiblePicks.isEmpty {
            pullable { emptyView }
        } else {
            list
        }
    }

    /// 당겨서 새로고침은 **스크롤 뷰가 있어야** 생긴다. 빈 화면과 오류 화면엔 스크롤할 게 없어서
    /// `.refreshable`이 통째로 죽어 있었다 — 정작 다시 받아봐야 하는 상태가 이 둘이다.
    /// `scrollBounceBehavior(.always)`가 내용이 짧아도 당겨지게 하고,
    /// `containerRelativeFrame`이 화면 높이를 채워 가운데 정렬을 그대로 남긴다.
    private func pullable<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        ScrollView {
            view().containerRelativeFrame(.vertical)
        }
        .scrollBounceBehavior(.always)
    }

    private var list: some View {
        ScrollView {
            // 카드가 좌우 여백을 직접 갖는다(카드마다 배경이 있어 여기서 주면 배경이 잘린다).
            LazyVStack(spacing: 14) {
                titleHeader
                ForEach(Array(visiblePicks.enumerated()), id: \.element.pickId) { index, pick in
                    PickCard(
                        pick: pick,
                        zoomNamespace: zoomNamespace,
                        onPlay: { open(pick, at: index) },
                        onReact: { react(pick, emoji: $0) },
                        // 게스트는 메뉴 안의 셋(신고·차단·삭제)을 하나도 끝까지 못 한다 —
                        // 신고는 401로 조용히 죽고, 차단은 해제 경로(마이페이지)가 게스트에 막혀 있다.
                        // 열어놓고 실패시키느니 여기서 로그인으로 보낸다. 읽기 항목은 메뉴에 없다.
                        // 항상 1뎁스부터. 안 되돌리면 지난번 신고 사유 화면이 그대로 뜬다.
                        onMenu: {
                            guard requireAccount() else { return }
                            menuStage = .actions
                            menuTarget = pick
                        },
                        coachAnchors: index == 0
                    )
                    .onAppear {
                        guard pick.pickId == visiblePicks.last?.pickId else { return }
                        Task { await loadMore() }
                    }
                }
            }
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
            .coachAnchor(.compose)
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
        // 스켈레톤은 첫 로드에만 켠다. 당겨서 새로고침 중에 켜면 지금 당기고 있는 스크롤 뷰가
        // 스켈레톤 분기로 교체돼 새로고침 인디케이터가 손안에서 사라진다(시스템 스피너로 충분하다).
        if !force { isLoading = true }
        loadFailed = false
        do {
            let res = try await session.api.send(.picks(), as: API.PickListResponse.self)
            picks = res.items
            nextCursor = res.hasMore ? res.nextCursor : nil
            #if DEBUG
            // 로컬 숨김·차단은 화면에서 조용히 지워버려서, 서버가 준 걸 못 받은 것처럼 보인다.
            // 실제로 한 번 밟았다 — DEBUG 목업 픽이 쓰던 id(1~6)를 신고해두면 같은 id의
            // 진짜 픽이 계속 숨겨진다. 가려진 장수를 찍어야 응답 문제와 구분된다.
            let hiddenCount = picks.count - visiblePicks.count
            if hiddenCount > 0 { print("[Picks] 로컬 숨김/차단으로 \(hiddenCount)장 가려짐") }
            #endif
        } catch {
            // 취소는 실패가 아니다. 탭을 옮기거나 화면을 덮으면 `.task`가 요청을 취소하는데,
            // 그걸 오류로 접으면 돌아왔을 때 "Couldn't load"가 그대로 남는다 —
            // `.task`는 뷰가 살아 있는 한 다시 안 돈다.
            var cancelled = false
            if let api = error as? APIError, case .transport(let underlying) = api {
                cancelled = (underlying as? URLError)?.code == .cancelled
            }
            // **보여줄 게 남아 있으면 실패 표시를 세우지 않는다.** 실패해도 이전 목록은 그대로
            // 두는데, 플래그만 켜두면 나중에 유저가 마지막 픽을 지워 목록이 빌 때
            // 그 지난 실패가 "불러오지 못했어요"로 튀어나온다(빈 화면이 맞다).
            if !cancelled { loadFailed = picks.isEmpty }
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
        // `is_official`이 "시드를 깔아둔 게 실제로 재생되나"를 답하는 유일한 축이다.
        // 서버가 필드를 안 내려주면 false로 접는다 — 세 번째 값(null)이 생기면 집계가 갈린다.
        PostHogSDK.shared.capture("pick_opened", properties: [
            "position": index, "is_official": pick.isOfficial == true, "source": "picks",
        ])
        playing = pick
    }

    /// 같은 이모지 재탭 = 해제, 다른 이모지 = 교체(서버 uq_pick_user가 1인 1개를 못박는다).
    /// 클라는 지금 🔥 하나만 보내지만 교체 경로는 남겨둔다 — 서버 화이트리스트가 5종이라
    /// 이전 버전에서 다른 이모지를 누른 유저의 `myReaction`이 그대로 내려온다.
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
                // **카드를 통째로 되돌리면 안 된다.** 그 사이 성공한 제목 수정까지 옛 값으로
                // 덮어쓴다(`title`이 낙관적 갱신 때문에 `var`다). 되돌릴 건 반응 두 필드뿐이다.
                picks[i].reactions = previous.reactions
                picks[i].myReaction = previous.myReaction
            }
        }
    }

    /// 신고한 카드는 즉시 로컬에서 숨긴다 — 운영자가 SQL로 처리하기 전 갭을 메우고,
    /// 안 사라지면 유저가 안 눌린 줄 안다.
    private func report(_ pick: API.Pick, reason: String, detail: String? = nil) {
        // 본문은 안 보낸다 — 자유 텍스트가 이벤트 속성에 들어가면 분석 도구에 개인정보가 샌다.
        PostHogSDK.shared.capture("pick_reported", properties: [
            "reason": reason, "has_detail": detail != nil,
        ])
        hiddenRaw = LocalModeration.adding(String(pick.pickId), to: hiddenRaw)
        showToast(String(localized: "Thanks — we'll take a look."))
        Task { try? await session.api.send(.reportPick(id: pick.pickId, reason: reason, detail: detail)) }

        // 닉네임 신고만 차단을 이어서 묻는다. 신고한 게 게시물이 아니라 **닉네임**인데
        // 카드 하나만 숨기면 그 닉네임은 그 사람의 다른 픽마다 계속 뜬다.
        // 자동으로 차단하진 않는다 — 신고 한 번에 그 사람 픽이 전부 사라지는 건 예상 밖 결과다.
        if reason == "NICKNAME" {
            blockFromReport = true
            blockTarget = pick
        }
    }

    /// 시트가 완전히 닫힌 뒤 호출된다. 여기서 alert를 띄워야 겹치지 않는다.
    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .reasons(let pick):
            // 같은 시트를 2뎁스로 다시 연다. 여기서 열어야 1뎁스 닫힘 애니메이션이 끝나 있다.
            menuStage = .reasons
            menuTarget = pick
        case .report(let pick, let reason, let detail):
            report(pick, reason: reason, detail: detail)
        case .block(let pick):
            blockFromReport = false
            blockTarget = pick
        case .delete(let pick): delete(pick)
        case .detail(let pick):
            menuStage = .detail
            menuTarget = pick
        case .rename(let pick):
            menuStage = .rename
            menuTarget = pick
        case .renamed(let pick, let title):
            rename(pick, to: title)
        case .cancel: break
        }
    }

    private func block(_ pick: API.Pick) {
        blockedRaw = LocalModeration.adding(pick.nickname, to: blockedRaw)
    }

    /// 제목만 바꾼다(§3). 낙관적으로 카드부터 고치고, 실패하면 되돌린 뒤 이유를 말한다 —
    /// 금칙어(400 `PICK_TITLE_BLOCKED`)는 서버가 로케일에 맞춰 문구를 내려주므로 그대로 띄운다.
    /// 조용히 되돌리면 유저는 저장이 된 줄 알고 나갔다가 옛 제목을 다시 본다.
    private func rename(_ pick: API.Pick, to title: String?) {
        guard let index = picks.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
        let previous = picks[index].title
        guard previous != title else { return }
        picks[index].title = title

        Task {
            do { try await session.api.send(.updatePickTitle(id: pick.pickId, title: title)) }
            catch {
                guard let i = picks.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
                picks[i].title = previous
                // `error`는 `any Error`라 enum 케이스 패턴이 바로 안 붙는다 — 먼저 캐스팅한다.
                if let apiError = error as? APIError, case .server(_, let message, _) = apiError {
                    showToast(message)
                } else {
                    showToast(String(localized: "Couldn't save. Try again."))
                }
            }
        }
    }

    private func delete(_ pick: API.Pick) {
        picks.removeAll { $0.pickId == pick.pickId }
        PostHogSDK.shared.capture("pick_deleted", properties: ["source": "picks"])
        Task {
            do {
                try await session.api.send(.deletePick(id: pick.pickId))
                // 프로필의 내 픽 목록·요약 행에도 반영시킨다. 서버 삭제가 끝난 뒤에만.
                session.deletedPickIds.insert(pick.pickId)
            } catch {
                await load(force: true)
            }
        }
    }

    /// 첫 픽을 올린 직후에만 묻는다. 반응 알림이 알릴 대상이 방금 생겼기 때문이고,
    /// 그전엔 알림이 무엇을 알리는지 유저가 겪은 적이 없다(로그인 직후 요청을 기각한 근거와 같다).
    /// 게스트는 애초에 게시를 못 하지만, 조건이 화면 밖 상태에 기대지 않게 여기서도 확인한다.
    private func offerPushIfNeeded() {
        guard justCreatedPick else { return }
        justCreatedPick = false
        guard !didOfferPush, session.authState == .signedIn else { return }
        Task {
            // 이미 답한 유저(.notDetermined 아님)에겐 물어봐야 소용이 없다.
            guard await session.pushAuthorizationUndecided() else { return }
            PostHogSDK.shared.capture("push_optin_shown", properties: ["source": "pick_created"])
            didOfferPush = true
            withAnimation(.easeOut(duration: 0.2)) { showPushOffer = true }
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

    private var blockBinding: Binding<Bool> {
        Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } })
    }

    private var blockAlertTitle: LocalizedStringKey {
        let nickname = blockTarget?.nickname ?? ""
        return blockFromReport ? "Block @\(nickname) too?" : "Block @\(nickname)"
    }

    private var blockAlertMessage: LocalizedStringKey {
        blockFromReport
            ? "You reported their nickname. Blocking hides every pick from them, and you can undo it from My Page."
            : "You won't see their picks anymore. Undo it from My Page."
    }
}

// MARK: - Menu sheet

enum PickMenuAction {
    /// 1뎁스에서 "신고"를 고른 것. 실제 신고가 아니라 **2뎁스를 열라는 뜻**이다.
    case reasons(API.Pick)
    /// 취소 버튼. 닫기만 하면 되지만 케이스로 둬야 `onDismiss`가 분기 없이 한 길로 흐른다.
    case cancel
    /// "기타"를 고른 것. 사유를 직접 받아야 해서 3뎁스(입력 폼)를 연다.
    case detail(API.Pick)
    /// 내 픽의 "제목 수정"을 고른 것. 실제 수정이 아니라 **입력 폼을 열라는 뜻**이다.
    case rename(API.Pick)
    /// 입력 폼에서 저장을 누른 것. 마지막 인자가 nil이면 제목을 지운다(폴백으로 돌아간다).
    case renamed(API.Pick, String?)
    /// 마지막 인자는 유저가 직접 쓴 사유. `OTHER`에서만 채워진다.
    case report(API.Pick, String, String?)
    case block(API.Pick)
    case delete(API.Pick)
}

/// `···` 메뉴. **`Menu`(팝오버)가 아니라 시트다** — 팝오버 앵커가 `LazyVStack` 안에서
/// 옛 좌표에 묶여 스크롤한 뒤 엉뚱한 자리에 떴다. 시트는 애초에 앵커가 없다.
///
/// 1뎁스(동작)와 2뎁스(신고 사유)는 **같은 시트를 닫았다 다시 여는** 방식이다.
/// 한 시트 안에서 내용만 갈아끼우면 높이가 툭 바뀌면서 어디서 온 화면인지가 안 읽힌다.
/// 전환 안전성은 `.sheet(onDismiss:)`가 보장한다 — 닫힘이 끝난 뒤에만 다음 것을 연다.
private struct PickMenuSheet: View {
    enum Stage { case actions, reasons, detail, rename }

    let pick: API.Pick
    let stage: Stage
    let choose: (PickMenuAction) -> Void

    /// 3뎁스(기타 사유) 입력. 서버 `detail VARCHAR(200)`과 맞춘 상한.
    @State private var detailText = ""
    /// 제목 수정 입력. 상한은 작성 화면과 같은 `PickTitle.maxLength`(30 grapheme).
    @State private var titleText = ""
    @FocusState private var focused: Bool
    private let maxLength = 200

    private var rowCount: Int {
        switch stage {
        case .reasons: 3
        // 내 픽 = 제목 수정·삭제, 남의 픽 = 신고·차단. 양쪽 다 두 줄이라 분기가 필요 없다.
        case .actions: 2
        case .detail, .rename: 0
        }
    }

    /// **실측하지 않는다.** `GeometryReader`로 재면 시트 높이가 콘텐츠 제안에 다시 영향을 줘서
    /// 값이 안 잡히는 순간 `.large`로 눌러앉는다(실제로 그렇게 떴다). 행이 1~3개뿐이라 셈이 더 싸다.
    /// 상수를 고치면 높이도 같이 맞아야 하므로 `Metrics` 한자리에 모아둔다.
    private var sheetHeight: CGFloat {
        // 입력 폼은 행 구조가 아니다. `ArtistRequestSheet`의 280에서 입력창이 2줄이라
        // 한 줄분(+22)만 더 준다 — 그 시트와 같아 보이게 하는 게 목적이다.
        if stage == .detail { return 302 }
        // 제목은 한 줄이라 입력창이 신고 사유(2줄)보다 낮다. 글자 수 표시 한 줄분(+20)만 더 준다.
        if stage == .rename { return 272 }
        return Metrics.top + CGFloat(rowCount) * Metrics.row
            + Metrics.gap + Metrics.cancel + Metrics.bottom
    }

    private enum Metrics {
        /// 드래그 인디케이터가 쓰는 위쪽 여백.
        static let top: CGFloat = 24
        static let row: CGFloat = 60
        static let gap: CGFloat = 16
        static let cancel: CGFloat = 56
        /// 홈 인디케이터에 취소 버튼이 닿지 않게.
        static let bottom: CGFloat = 24
        /// 라벨은 32, 구분선·취소 버튼은 16. 글이 선보다 안쪽에 들어가야 행으로 읽힌다.
        static let labelInset: CGFloat = 32
        static let edgeInset: CGFloat = 16
    }

    var body: some View {
        Group {
            if stage == .detail {
                // 여백은 `ArtistRequestSheet`와 똑같이 사방 24 한 번으로 준다.
                // 바깥에서 top/bottom을 또 주면 그 시트와 수치가 어긋난다.
                detailForm.padding(24)
            } else if stage == .rename {
                renameForm.padding(24)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    rows
                    Spacer(minLength: Metrics.gap)
                    cancelButton
                }
                .padding(.top, Metrics.top)
                .padding(.bottom, Metrics.bottom)
            }
        }
        // 위로 붙인다. 안 주면 짧은 콘텐츠가 시트 한가운데에 떠서 위아래가 휑해진다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(sheetHeight)])
        // 입력 폼엔 안 띄운다 — `ArtistRequestSheet`에도 없고, 인디케이터가 차지하는
        // 위 20pt 때문에 제목 시작 높이가 그 시트와 어긋난다.
        .presentationDragIndicator(stage == .detail || stage == .rename ? .hidden : .visible)
        // 지면·카드보다 한 단 밝게. 카드와 같은 색이면 시트가 지면에 눌어붙어 보인다.
        .presentationBackground(DSColor.pickElevated)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    /// 기타 사유 입력. `ArtistRequestSheet`와 같은 구성(제목 → 설명 → 입력 → 전송)이고
    /// 색만 다크로 바꿨다. 다른 폼을 새로 발명할 이유가 없다.
    private var detailForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happened?")
                .font(DSTypography.title2)
                .foregroundStyle(.white)
            Text("Tell us what's wrong. We read every report.")
                .font(DSTypography.body)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            // 아티스트 이름은 한 줄이면 되지만 신고 사유는 서술이라 2줄을 미리 비워둔다.
            // 높이는 `frame`으로 못 박는다 — 줄 수에 따라 폼이 자라면 고정 detent와 어긋난다.
            TextField("", text: $detailText, prompt: detailPrompt, axis: .vertical)
                .font(DSTypography.body)
                .foregroundStyle(.white)
                .focused($focused)
                .lineLimit(2, reservesSpace: true)
                .onChange(of: detailText) { _, new in
                    if new.count > maxLength { detailText = String(new.prefix(maxLength)) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(height: 68, alignment: .top)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            Button {
                let trimmed = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
                choose(.report(pick, "OTHER", trimmed.isEmpty ? nil : trimmed))
            } label: {
                Text("Send")
                    .font(DSTypography.bodyMedium)
                    // 밝은 보라 위엔 흰 글씨가 안 읽힌다. 지면색을 글자로 되돌려 쓴다.
                    .foregroundStyle(DSColor.pickBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DSColor.pickAccent.opacity(canSend ? 1 : 0.35),
                                in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSend)
        }
        // 여백은 호출부의 `.padding(24)` 하나뿐이다. 여기서 또 주면 좌우만 48이 된다.
        .onAppear { focused = true }
    }

    /// 제목 수정. **곡 구성은 안 건드린다** — 삭제 후 재게시는 `pick_id`가 바뀌어 반응이 통째로 날아간다.
    /// 폼 구성은 `detailForm`과 같고, 입력이 한 줄이라 글자 수 표시가 붙는다(작성 화면과 같은 규칙).
    private var renameForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit title")
                    .font(DSTypography.title2)
                    .foregroundStyle(.white)
                Spacer()
                Text(verbatim: "\(titleText.count) / \(PickTitle.maxLength)")
                    .font(.system(size: 12))
                    .foregroundStyle(titleText.count >= PickTitle.maxLength
                                     ? DSColor.destructive : .white.opacity(0.35))
                    .monospacedDigit()
            }

            // 플레이스홀더 = 비웠을 때 실제로 나올 제목. 작성 화면과 같은 규칙이라
            // "비우면 이렇게 된다"를 따로 설명할 필요가 없다.
            TextField("", text: $titleText, prompt: renamePrompt)
                .font(DSTypography.body)
                .foregroundStyle(.white)
                .tint(DSColor.pickAccent)
                .focused($focused)
                .onChange(of: titleText) { _, new in
                    // Swift는 grapheme, Postgres varchar는 code point로 센다 — 길이 합의는
                    // 포기하고 클라가 30에서 자르고 서버는 컬럼 상한만 지킨다.
                    if new.count > PickTitle.maxLength {
                        titleText = String(new.prefix(PickTitle.maxLength))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            Button {
                choose(.renamed(pick, PickTitle.normalized(titleText)))
            } label: {
                Text("Save")
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.pickBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DSColor.pickAccent, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        // 비워서 저장할 수 있다 — 그건 실수가 아니라 "제목을 지우고 폴백으로 돌린다"는 뜻이다.
        .onAppear {
            titleText = pick.title ?? ""
            focused = true
        }
    }

    private var renamePrompt: Text {
        Text(PickTitle.fallback(for: pick)).foregroundColor(.white.opacity(0.35))
    }

    /// 플레이스홀더는 흰색이 아니라 옅게. `prompt:`로 넘겨야 색을 줄 수 있다.
    private var detailPrompt: Text {
        Text("Tell us what's wrong").foregroundColor(.white.opacity(0.35))
    }

    /// **비워서 보낼 수 없다.** 기타는 사유가 본문에만 있어서, 빈 채로 오면 운영자가 볼 게 없다.
    private var canSend: Bool {
        !detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var rows: some View {
        switch stage {
        case .reasons:
            row("Inappropriate nickname") { choose(.report(pick, "NICKNAME", nil)) }
            divider
            row("Inappropriate content") { choose(.report(pick, "CONTENT", nil)) }
            divider
            // 사유를 직접 받는다 — 이것만 한 단계 더 간다.
            row("Something else") { choose(.detail(pick)) }
        case .actions:
            if pick.isMine {
                // 곡 구성은 없다 — 제목만 고칠 수 있다(§3). 곡을 바꾸는 건 삭제 후 재게시고,
                // 그러면 `pick_id`가 바뀌어 붙어 있던 반응이 통째로 날아간다.
                row("Edit title") { choose(.rename(pick)) }
                divider
                row("Delete", destructive: true) { choose(.delete(pick)) }
            } else {
                row("Report") { choose(.reasons(pick)) }
                divider
                // 닉네임이 20자까지 온다. 끝을 자르면 ko에서 "차단"이, 앞을 자르면 en에서
                // "Block"이 통째로 날아간다 — 가운데를 잘라야 동사가 양쪽 다 살아남는다.
                row("Block @\(pick.nickname)", destructive: true, truncation: .middle) {
                    choose(.block(pick))
                }
            }
        case .detail, .rename:
            // 입력 폼은 `detailForm`/`renameForm`이 그린다. 여기까지 오지 않는다.
            EmptyView()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, Metrics.edgeInset)
    }

    /// 아무것도 안 고르고 닫기. 아래로 쓸어도 닫히지만, **파괴적 항목만 있는 시트에서
    /// 빠져나갈 길이 제스처뿐이면 유저가 갇힌 것처럼 느낀다.**
    private var cancelButton: some View {
        Button { choose(.cancel) } label: {
            Text("Cancel")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.cancel)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.edgeInset)
    }

    /// 라벨은 `LocalizedStringKey`로 받는다 — `String`이면 현지화가 조용히 죽는다.
    private func row(_ text: LocalizedStringKey,
                     destructive: Bool = false,
                     truncation: Text.TruncationMode = .tail,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(destructive ? DSColor.destructive : .white)
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.labelInset)
                .frame(height: Metrics.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

/// 뉴스 피드형 카드: **헤더(누가·언제·`···`) → 제목 → 미디어 → 버블 행.**
/// 라운드 24pt 카드로 돌아왔지만 이전 상자와는 다르다 — 안쪽 요소가 카드 폭을 꽉 쓰고,
/// 반응은 억지로 낀 아이콘이 아니라 **버블(알약 칩)** 안에 들어가 배경을 갖는다.
/// 인터랙션은 **구조로 가른다**: 미디어만 탭 제스처를 갖고, 버블·`···`는 형제 노드다.
struct PickCard: View {
    let pick: API.Pick
    let zoomNamespace: Namespace.ID
    let onPlay: () -> Void
    /// nil이면 반응 버블이 **표시 전용**이 된다(프로필의 내 픽 섹션 — 할 수 있는 건 조회와 삭제뿐).
    let onReact: ((String) -> Void)?
    let onMenu: () -> Void
    /// 코치마크가 가리킬 카드인가. 목록 첫 장에만 켠다 — 여러 장이 앵커를 올리면
    /// 어느 카드를 뚫을지가 스크롤 위치에 따라 흔들린다.
    var coachAnchors: Bool = false

    @Environment(AppSession.self) private var session
    /// 렌더가 끝난 공유 카드. 시트는 카드마다 하나씩 붙지만 뜨는 건 누른 카드 하나뿐이다
    /// (화면 루트에 몰면 이 파일의 `.sheet` 세 개와 서로 잡아먹는다).
    @State private var shareImage: ShareImage?
    @State private var isPreparingShare = false

    private var title: String { pick.title ?? PickTitle.fallback(for: pick) }

    /// 곡 목록은 목록 응답에 없어서 재생용 상세를 한 번 더 부른다. 실패하면 곡 줄 없이
    /// 커버·제목만으로 렌더한다 — 공유가 통째로 막히는 것보다 낫다.
    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        // 시트를 연 순간만 잡는다. 실제로 어디에 올렸는지는 시스템이 안 알려준다.
        PostHogSDK.shared.capture("pick_shared")
        let detail = try? await session.api.send(.pickDetail(id: pick.pickId), as: API.PickDetail.self)
        guard let image = await PickShareCard.render(pick: pick, tracks: detail?.items ?? []) else { return }
        shareImage = ShareImage(image: image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // 제목이 미디어 **위**에 온다 — 커버를 보기 전에 무슨 묶음인지 읽힌다.
            // 줄 수 제한 없음: 입력이 30 grapheme으로 잘리고 폴백 제목도 길어야 두어 줄이라
            // 카드 높이가 들쭉날쭉해질 여지가 작다. 말줄임보다 다 보여주는 쪽이 낫다.
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            media
            bubbleRow
        }
        .padding(14)
        .background(DSColor.pickSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .sheet(item: $shareImage) { ShareSheet(items: [ImageShareSource(image: $0.image)]) }
    }

    /// 작성자가 맨 위 한 줄. `···`는 원형 버튼으로 오른쪽 끝 — 아트워크 위에 얹지 않는다.
    private var header: some View {
        HStack(spacing: 6) {
            // 아바타(닉네임 첫 글자 원)는 뺐다. 대부분이 `digger_` 프리픽스 자동 닉네임이라
            // 모든 카드에 같은 `D`가 찍혀 **구분이 아니라 반복**만 만들어냈다.
            // 원을 없앤 자리는 두 줄을 한 줄로 합쳐 메운다 — 두 줄짜리 텍스트 블록은
            // 애초에 42pt 원의 높이를 맞추려고 있던 것이라, 원이 빠지면 같이 빠져야 한다.
            Text(verbatim: "@\(pick.nickname)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            // 운영자 표시. 닉네임을 못 밀어내게 `layoutPriority`는 안 준다 — 닉네임이 길면
            // 닉네임이 잘리고 씰은 남는다(씰은 폭이 고정이라 잘릴 수가 없다).
            if pick.isOfficial == true {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.pickAccent)
                    .accessibilityLabel("Official")
            }
            Text(verbatim: "·")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text(pick.createdAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                // 닉네임이 20자까지 오므로, 줄이 넘치면 짧고 사실인 쪽(시간)을 지킨다.
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            overflowMenu
        }
    }

    /// 카드 폭을 꽉 채우는 220pt 미디어. 배경은 1번 곡 커버를 크게 흐린 것 —
    /// 픽마다 색이 달라 그 픽의 것으로 읽히고, 단색 블록처럼 비어 보이지 않는다.
    private var media: some View {
        ZStack {
            // 옵셔널 체이닝이면 `URL??`가 돼 AsyncImage에 안 들어간다.
            AsyncImage(url: pick.thumbnails.first.flatMap { $0.itunesArtworkURL(size: 400) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSColor.pickBackground
            }
            .blur(radius: 28)
            // 흐린 커버가 밝으면 위에 얹은 커버 스택과 대비가 죽는다.
            .overlay(Color.black.opacity(0.45))
            PickThumbnailStack(urls: pick.thumbnails, trackCount: pick.trackCount)
                .pickZoomSource(id: pick.pickId, in: zoomNamespace)
        }
        // 높이는 비율이 아니라 고정값이다. `aspectRatio(.fit)`는 세로 제안이 없는 ScrollView
        // 안에서 자식 이상 크기를 물고 폭이 줄어들 수 있다.
        // `maxWidth`와 `height`는 한 호출에 못 섞으므로 min/max를 같은 값으로 묶는다.
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        // blur는 프레임 밖으로 번진다 — 자르는 김에 모서리도 여기서 깎는다.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .coachAnchor(coachAnchors ? .play : nil)
    }

    /// 버블 행 — 반응·곡 수는 왼쪽, 공유는 오른쪽 끝.
    /// 반응만 버튼이고 곡 수는 표시다. 버블이 배경을 갖는 덕에 이모지가 지면에 겉돌지 않는다.
    private var bubbleRow: some View {
        let count = pick.reactions[PickReaction.primary] ?? 0
        let mine = pick.myReaction == PickReaction.primary
        return HStack(spacing: 8) {
            Group {
                if let onReact {
                    Button { onReact(PickReaction.primary) } label: {
                        reactionBubble(count: count, mine: mine)
                    }
                    .buttonStyle(.plain)
                } else {
                    reactionBubble(count: count, mine: mine)
                }
            }
            .animation(.easeOut(duration: 0.15), value: mine)
            .coachAnchor(coachAnchors ? .react : nil)
            .accessibilityLabel(PickReaction.label)
            .accessibilityValue(Text(verbatim: "\(count)"))
            .accessibilityAddTraits(mine ? .isSelected : [])

            // 곡 수는 표시 전용이라 **알약을 안 씌운다.** 같은 버블을 두르면 누르면 뭔가
            // 일어날 것처럼 보인다 — 이 행에서 배경 있는 것만 버튼이라는 규칙을 만든다.
            HStack(spacing: 5) {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold))
                // 단위까지 붙여야 숫자가 뭘 세는지가 아이콘 해석에 안 기댄다.
                Text("\(pick.trackCount) tracks")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.45))
            .padding(.leading, 4)

            Spacer(minLength: 0)

            // 9:16 이미지 카드로 내보낸다. 텍스트만 보내면 받는 쪽엔 곡이 하나도 안 보이고,
            // 픽을 열어줄 웹 페이지가 없어서 링크로도 못 만든다(`PickShareCardView`).
            Button { Task { await prepareShare() } } label: {
                bubble {
                    if isPreparingShare {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            // 심볼 무게중심이 아래로 처져 보여서 1pt 올린다.
                            .offset(y: -1)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(isPreparingShare)
            .coachAnchor(coachAnchors ? .share : nil)
            .accessibilityLabel("Share")
        }
    }

    private func reactionBubble(count: Int, mine: Bool) -> some View {
        bubble(tinted: mine) {
            Text(verbatim: PickReaction.primary).font(.system(size: 15))
            // 카운트 0이면 숫자를 안 그린다 — "0"은 비어 있다는 사실을 굳이 읽어주는 숫자다.
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mine ? DSColor.brand : .white.opacity(0.8))
                    .lineLimit(1)
            }
        }
    }

    /// 버블 하나. 알약 배경이 있으니 이모지도 "얹힌 스티커"가 아니라 칩 내용물로 읽힌다.
    private func bubble<Content: View>(tinted: Bool = false,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(tinted ? DSColor.brand.opacity(0.18) : .white.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
    }

    /// `Menu`가 아니라 그냥 버튼이다. **`Menu`의 팝업은 스크롤한 뒤 엉뚱한 자리에 떴다** —
    /// `LazyVStack` 안에서 앵커가 옛 좌표에 묶인다. 항목을 목록 밖(화면 아래 고정)에서
    /// 띄우면 앵커라는 개념 자체가 없어져 문제가 사라진다.
    private var overflowMenu: some View {
        Button(action: onMenu) {
            // 원형 배경을 없앴다. 36pt 원이 헤더 행 높이를 혼자 결정해서 닉네임 위아래로
            // 빈 9pt씩이 생겼고, 그게 아바타를 뺀 뒤 "허전한" 간격의 정체였다.
            // ponytail: 28pt는 44pt 권장보다 작다. 빈도 낮은 보조 메뉴라 감수 — 오탭이 보고되면 32로.
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, height: 28, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            // 헤더 — 실제 카드와 같은 한 줄(아바타 없음) + 오른쪽 `···`.
            HStack(spacing: 8) {
                bar(width: 110, height: 14, radius: 6)
                bar(width: 52, height: 12, radius: 6)
                Spacer(minLength: 0)
                bar(width: 18, height: 4, radius: 2)
            }
            .frame(height: 28)
            bar(width: 210, height: 16, radius: 6)
            // 미디어 — 실제 카드와 같은 220pt여야 도착 순간 목록이 안 튄다.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.06))
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
            HStack(spacing: 12) {
                bar(width: 64, height: 36, radius: 18)
                bar(width: 34, height: 13, radius: 6)
                Spacer(minLength: 0)
                bar(width: 52, height: 36, radius: 18)
            }
        }
        .padding(14)
        .background(DSColor.pickSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
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
extension View {
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
