import SwiftUI

/// 내가 요청한 아티스트 히스토리. 마이페이지에서 진입한다.
/// 우상단 + 로 요청 시트를 띄우고, 시트가 닫히면 목록을 다시 받는다.
struct ArtistRequestHistoryView: View {
    @Environment(AppSession.self) private var session

    @State private var items: [API.ArtistRequest] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showRequestSheet = false

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                // ponytail: 편집 모드는 List가 EditButton + onDelete로 이미 제공한다.
                // 크레이트·픽처럼 배지를 직접 그리지 않는 이유는 여기만 List라서다.
                List {
                    ForEach(items) { request in
                        RequestRow(request: request)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await delete(request) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        // offsets는 화면 순서 기준이다. 지울 대상을 먼저 값으로 뽑아 두지 않으면
                        // 낙관적 제거로 배열이 줄어든 뒤 인덱스가 밀린다.
                        let targets = offsets.map { items[$0] }
                        Task { for request in targets { await delete(request) } }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(DSColor.background)
        .navigationTitle("Artist Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().tint(DSColor.brand)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRequestSheet = true } label: { Image(systemName: "plus") }
                    .tint(DSColor.brand)
            }
        }
        .sheet(isPresented: $showRequestSheet, onDismiss: { Task { await load() } }) {
            ArtistRequestSheet()
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(loadFailed ? String(localized: "Couldn't load")
                            : String(localized: "No requests yet"))
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            if !loadFailed {
                Text("Tap + to request an artist.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 낙관적 제거 후 서버 삭제. 실패하면 목록을 원복한다.
    private func delete(_ request: API.ArtistRequest) async {
        let previous = items
        items.removeAll { $0.id == request.id }
        do {
            try await session.api.send(.deleteArtistRequest(id: request.id))
        } catch {
            items = previous
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            items = try await session.api.send(.artistRequests, as: API.ArtistRequestListResponse.self).items
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

private struct RequestRow: View {
    let request: API.ArtistRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.artistName)
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                StatusBadge(status: request.status)
            }
            // 취소 사유는 있을 때만.
            if request.status == .canceled, let reason = request.cancelReason, !reason.isEmpty {
                Text(reason)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Text(request.createdAt, format: .dateTime.year().month().day())
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let status: API.RequestStatus

    private var label: LocalizedStringKey {
        switch status {
        case .pending: "Pending"
        case .added: "Added"
        case .canceled: "Canceled"
        }
    }

    private var color: Color {
        switch status {
        case .pending: DSColor.textSecondary
        case .added: DSColor.brand
        case .canceled: DSColor.destructive
        }
    }

    var body: some View {
        Text(label)
            .font(DSTypography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
