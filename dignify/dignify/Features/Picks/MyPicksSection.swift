import SwiftUI
import PostHog

/// 프로필의 "내가 만든 픽" — **요약 행 한 줄**이고, 목록은 눌러서 들어가는 별도 화면이다.
/// 만든 것 → 모은 것 순으로 `Your crate` 바로 위에 온다.
///
/// 카드를 프로필에 그대로 쌓지 않는 이유: `PickCard` 한 장이 350pt쯤이라 세 장이면 통계
/// 블록 전체보다 길어진다. 크레이트가 이미 미리보기 + See all로 접혀 있어서, 픽만 펼쳐두면
/// 한 화면에 규칙이 두 개가 된다. 상단 range 토글(통계 전용)이 아래 전체에 걸리는 것처럼
/// 보이던 것도 덩어리가 줄면서 같이 사라진다.
///
/// **할 수 있는 건 조회·제목 수정·삭제다**(`13_mypage_ia_after_picks.md` §3).
/// 곡 구성 수정은 삭제 후 재게시다 — 반응이 붙은 픽의 곡이 사후에 바뀌면 그 반응이 무엇에
/// 대한 것이었는지가 무너진다. 제목 수정은 픽 탭과 이 화면 둘 다에서 되지만 낙관적 갱신과
/// 롤백은 `PickTitle.rename` 한 벌이다.
struct MyPicksSection: View {
    @Environment(AppSession.self) private var session

    /// 첫 페이지는 여기서 받아 요약 행을 그리고, **그대로 목록 화면에 물려준다**(재조회 0).
    /// 목록에서 지운 픽이 돌아왔을 때 행에도 반영되도록 바인딩으로 넘긴다 —
    /// 크레이트가 `HypeCollection(items: $hypes)`로 쓰는 방식과 같다.
    @State private var picks: [API.Pick] = []
    @State private var nextCursor: String?
    /// 한 번 받아오면 재진입해도 다시 안 받는다(크레이트와 같은 규칙).
    @State private var loaded = false

    /// 픽 탭에서 지운 픽은 이 배열엔 아직 남아 있다. 요약 행과 개수가 어긋나지 않게 같이 거른다.
    private var visible: [API.Pick] {
        picks.filter { !session.deletedPickIds.contains($0.pickId) }
    }

    var body: some View {
        // 픽이 없으면 섹션을 통째로 숨긴다 — 안 만드는 유저가 다수라 빈 껍데기를 상시 노출할
        // 이유가 없다. 로딩 스켈레톤도 같은 이유로 안 깐다(대부분에겐 결국 사라질 자리다).
        VStack(alignment: .leading, spacing: 12) {
            if let latest = visible.first {
                // 구분선은 **섹션이 자기 위의 것을 갖는다.** 픽이 없어 이 블록이 통째로 빠지면
                // 선도 같이 빠져서, 통계와 크레이트 사이에 선이 두 줄 남지 않는다.
                Divider().padding(.horizontal, 20)
                Text("Your picks")
                    .font(DSTypography.title2)
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, 20)
                NavigationLink {
                    MyPicksView(picks: $picks, nextCursor: $nextCursor)
                } label: {
                    summaryRow(latest)
                }
                .buttonStyle(.plain)
            }
        }
        .task { await load() }
    }

    private var countText: String {
        nextCursor == nil ? "\(visible.count)" : "\(visible.count)+"
    }

    /// 가장 최근 픽 한 장을 얼굴로 세운다. 개수만 있는 행은 무엇이 들어 있는지를 안 알려준다.
    private func summaryRow(_ latest: API.Pick) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: latest.thumbnails.first.flatMap { $0.itunesArtworkURL(size: 200) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSColor.pickBackground
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(latest.title ?? PickTitle.fallback(for: latest))
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                // 다음 페이지가 남아 있으면 지금 받은 수가 총량이 아니다 — "20+"로 정직하게 쓴다.
                // 숫자를 **String으로 만들어 넣는다**: `%lld picks`와 `%lld+ picks`를 따로 두면
                // 문자열 카탈로그가 같은 심볼을 만들려다 빌드가 깨진다(키가 두 개일 이유도 없다).
                Text("\(countText) picks")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    /// ponytail: 실패하면 조용히 접는다 — 섹션이 없는 화면과 같아지고, 다시 들어오면 재시도된다.
    /// 프로필 본문(통계·크레이트)이 이미 각자 오류를 말하고 있어 여기까지 오류 문구를 더하지 않는다.
    private func load() async {
        guard !loaded else { return }
        guard let res = try? await session.api.send(.picks(mine: true), as: API.PickListResponse.self)
        else { return }
        picks = res.items
        nextCursor = res.hasMore ? res.nextCursor : nil
        loaded = true
    }
}

// MARK: - 목록 화면

/// 내가 만든 픽 전체. 카드·페이징은 `PickListView` 것을 그대로 쓴다 —
/// 이 화면의 신규 코드는 껍데기와 삭제 확인뿐이다.
/// 첫 페이지는 섹션이 이미 받아뒀으므로 여기서 다시 안 부른다(이어받기만 한다).
private struct MyPicksView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Binding var picks: [API.Pick]
    @Binding var nextCursor: String?

    @State private var isPaging = false
    @State private var playing: API.Pick?
    @State private var menuTarget: API.Pick?
    @State private var menuStage: PickMenuSheet.Stage = .actions
    /// 시트가 완전히 닫힌 뒤에 실행할 것. 닫히는 중에 다음 시트를 열면 서로 잡아먹는다.
    @State private var pendingAction: PickMenuAction?
    @State private var errorMessage: String?
    @Namespace private var zoomNamespace

    /// 섹션과 같은 필터. 픽 탭에서 지운 픽이 이 목록에 남아 있으면 안 된다.
    private var visible: [API.Pick] {
        picks.filter { !session.deletedPickIds.contains($0.pickId) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(visible) { pick in
                    PickCard(
                        pick: pick,
                        zoomNamespace: zoomNamespace,
                        onPlay: { open(pick) },
                        // 내 픽에 내가 반응하는 자리가 아니다. 숫자는 보여주되 버튼은 아니다.
                        onReact: nil,
                        // 픽 탭의 `···`와 같은 시트다. 내 픽이므로 제목 수정·삭제 두 줄이 뜬다.
                        onMenu: {
                            menuStage = .actions
                            menuTarget = pick
                        }
                    )
                    .onAppear {
                        guard pick.pickId == visible.last?.pickId else { return }
                        Task { await loadMore() }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(DSColor.background)
        .navigationTitle("Your picks")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { pick in
            FeedView(mode: .pick(id: pick.pickId, nickname: pick.nickname))
                .pickZoomTransition(id: pick.pickId, in: zoomNamespace)
        }
        // 1뎁스(제목 수정·삭제)와 제목 입력 폼이 **같은 시트 하나**다. 고른 것은 `pendingAction`에
        // 담아뒀다가 `onDismiss`에서 실행한다 — 닫힘이 끝난 뒤라야 다음 시트가 안전하게 뜬다.
        .sheet(item: $menuTarget, onDismiss: runPendingAction) { pick in
            PickMenuSheet(pick: pick, stage: menuStage) { action in
                pendingAction = action
                menuTarget = nil
            }
        }
        .alert("Couldn't save", isPresented: errorBinding, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// 시트가 완전히 닫힌 뒤 호출된다. 신고·차단은 내 픽에 뜻이 없어 이 화면엔 오지 않는다.
    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .rename(let pick):
            menuStage = .rename
            menuTarget = pick
        case .renamed(let pick, let title):
            PickTitle.rename(pick, to: title, in: $picks, api: session.api) { errorMessage = $0 }
        case .delete(let pick):
            delete(pick)
        default:
            break
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        // mine은 커서 요청에도 실어야 한다 — 커서엔 mine이 안 들어 있어 빠지면 남의 픽이 섞인다.
        guard let res = try? await session.api.send(.picks(cursor: cursor, mine: true),
                                                    as: API.PickListResponse.self)
        else { return }
        picks.append(contentsOf: res.items)
        nextCursor = res.hasMore ? res.nextCursor : nil
    }

    private func open(_ pick: API.Pick) {
        // position은 안 싣는다 — 여기 순서는 내 픽 최신순이라 목록에서의 노출 순위와 뜻이 다르다.
        // source로 갈라야 픽 탭 퍼널에 프로필 재생이 섞여 들어가지 않는다.
        PostHogSDK.shared.capture("pick_opened", properties: [
            "is_official": pick.isOfficial == true, "source": "profile",
        ])
        playing = pick
    }

    /// 낙관적 제거. 바인딩이라 프로필 요약 행도 같이 줄어든다.
    /// 실패하면 **제자리에 되돌린다** — 섹션이 첫 페이지를 한 번만 받아서(`loaded`),
    /// 여기서 안 되돌리면 앱을 다시 켜기 전까지 서버엔 살아 있는 픽이 화면에서만 사라진다.
    private func delete(_ pick: API.Pick) {
        guard let index = picks.firstIndex(where: { $0.pickId == pick.pickId }) else { return }
        picks.remove(at: index)
        PostHogSDK.shared.capture("pick_deleted", properties: ["source": "profile"])
        // 마지막 한 장을 지웠으면 이 화면엔 볼 게 없다. 빈 목록을 띄워두면 뒤로 가는 것 말고
        // 할 게 없는 화면이 남는다 — 지운 결과(줄어든 요약 행)는 프로필에서 바로 보인다.
        if visible.isEmpty { dismiss() }
        Task {
            do {
                try await session.api.send(.deletePick(id: pick.pickId))
                // 픽 탭이 들고 있는 자기 목록에서도 빠지게 알린다. 서버 삭제가 끝난 뒤에만.
                session.deletedPickIds.insert(pick.pickId)
            } catch {
                picks.insert(pick, at: min(index, picks.count))
            }
        }
    }
}
