import SwiftUI
import PostHog

/// 추천 기준 곡 고르기. 하입한 곡 중에서 최대 `limit`개를 고정하면, 서버가 최근 하입 대신
/// 그 곡들만 시드로 쓴다(`MoodRecommender.findSeeds`).
///
/// **아무것도 고르지 않은 상태가 기본이고 그게 정상이다.** 그때는 종전대로 최근 하입 세 곡이
/// 시드라, 이 화면에 한 번도 안 들어온 유저의 피드가 달라지지 않는다.
///
/// 목록은 `HypeCollection`을 선택 모드로 재사용한다 — 날짜 묶음, 페이지네이션, 썸네일 셀이
/// 하입 기록 화면과 같아야 "내가 담은 곡 중에서 고르는 것"이라는 게 한눈에 읽힌다.
struct SeedPickerView: View {
    /// 서버 `SeedTracksUpdateRequest @Size(max)` 및 `MoodRecommender.SEEDS`와 같아야 한다.
    /// 더 고르게 두면 서버가 400으로 튕기거나 조용히 잘라낸다.
    private static let limit = 3

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var items: [API.HypeItem] = []
    @State private var selected: Set<Int> = []
    /// 저장 성공 여부를 판단할 기준. 서버에서 받은 그대로를 들고 있다가 비교한다.
    @State private var savedSelection: Set<Int> = []
    @State private var nextCursor: Int?
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var saveFailed = false
    /// 이 화면 코치마크를 이미 봤는지. **읽고 나가면 아무것도 안 바뀌는 화면이라**
    /// 곡 하나를 실제로 골라 저장하는 데까지 데려간다.
    @AppStorage("seenSeedCoach") private var seenSeedCoach = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(DSColor.background)
        .navigationTitle("Recommend from")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .tint(DSColor.brand)
                        .coachAnchor(.seedSave)
                        // 바꾼 게 없으면 누를 이유가 없다. 저장을 눌렀는데 아무 일도 안 일어나면
                        // 실패한 것처럼 보인다.
                        .disabled(selected == savedSelection)
                }
            }
        }
        .task { await load() }
        // 고를 곡이 있을 때만. 빈 목록에서 "눌러 보세요"는 가리킬 데가 없다.
        .coachMarks(SeedCoach.steps, screen: "seed_picker",
                    isActive: !seenSeedCoach && !isLoading && !items.isEmpty) {
            seenSeedCoach = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick up to \(Self.limit) tracks. The feed then follows only these.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            Text("Pick none and the feed follows your \(Self.limit) most recent hypes, same as before.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
            // 꺼진 채로 들어올 수 있다. 고른 것이 지금 아무 데도 안 쓰인다는 걸 말해 주지 않으면
            // 저장하고 나서 피드가 그대로인 것을 고장으로 읽는다.
            if !session.diggingMode {
                Text("Turn on \"Follow my hypes\" for these to take effect.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.brand)
            }
            if saveFailed {
                Text("Couldn't save. Please try again.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.destructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            // 하입이 없으면 고를 것도 없다. 빈 목록에 "고르세요"만 남기지 않는다.
            Text(loadFailed ? String(localized: "Couldn't load") : String(localized: "No hyped tracks yet"))
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                HypeCollection(items: $items,
                               onReachEnd: { await loadMore() },
                               selection: $selected,
                               selectionLimit: Self.limit,
                               coachAnchors: true)
                    .padding(.top, 8)
            }
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let res = try await session.api.send(.myHypes(), as: API.HypeListResponse.self)
            items = res.items
            nextCursor = res.nextCursor
            // 첫 페이지 밖에 고정된 곡이 있어도 여기선 안 보인다. 그래도 목록을 더 받으면
            // 합쳐지므로, 저장 시 화면에 없는 선택을 지우지 않게 합집합으로 들고 간다.
            selected = Set(res.items.filter { $0.isSeed == true }.map(\.trackId))
            savedSelection = selected
            // 저장까지 간 비율을 보려면 분모가 필요하다. 목록을 못 받은 진입은 세지 않는다 —
            // 그때는 고를 수가 없어서 저장 안 한 게 유저의 선택이 아니다.
            PostHogSDK.shared.capture("seed_picker_opened",
                                      properties: ["pinned": savedSelection.count])
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        guard let res = try? await session.api.send(.myHypes(cursor: cursor), as: API.HypeListResponse.self)
        else { return }
        items.append(contentsOf: res.items)
        nextCursor = res.nextCursor
        // 뒤 페이지에 있던 고정 곡을 이제야 알게 된다. 유저가 아직 손대지 않은 것만 더한다 —
        // 방금 해제한 곡이 페이지가 로드되면서 되살아나면 안 된다.
        let newlyKnown = res.items.filter { $0.isSeed == true }.map(\.trackId)
        for id in newlyKnown where !savedSelection.contains(id) {
            selected.insert(id)
            savedSelection.insert(id)
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
