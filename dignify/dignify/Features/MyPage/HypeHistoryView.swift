import SwiftUI

/// 하입 기록 전체 화면 — 커서 페이지네이션으로 모든 하입을 날짜별로 보여준다.
struct HypeHistoryView: View {
    @Environment(AppSession.self) private var appSession

    @State private var items: [API.HypeItem] = []
    @State private var nextCursor: Int?
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                ProgressView().padding(.vertical, 60)
            } else if items.isEmpty {
                Text(loadFailed ? "불러오지 못했어요" : "아직 하입한 트랙이 없어요")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.vertical, 60)
            } else {
                HypeCollection(
                    items: $items,
                    onReachEnd: { await loadMore() },
                    onReloadNeeded: { await load() }
                )
                .padding(.top, 16)
            }
        }
        .background(DSColor.background)
        .navigationTitle("하입 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let res = try await appSession.api.send(.myHypes(), as: API.HypeListResponse.self)
            items = res.items
            nextCursor = res.nextCursor
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        guard let res = try? await appSession.api.send(.myHypes(cursor: cursor), as: API.HypeListResponse.self)
        else { return }
        items.append(contentsOf: res.items)
        nextCursor = res.nextCursor
    }
}
