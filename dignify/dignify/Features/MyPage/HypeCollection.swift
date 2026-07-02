import SwiftUI

/// 하입 트랙을 날짜(일 단위)별 가로 스크롤로 렌더링하는 재사용 컴포넌트.
/// 셀 탭 재생 / 롱프레스 액션시트(상세·제거) / 끝 도달 시 페이지네이션 트리거를 포함한다.
/// 마이페이지(최근 N일 미리보기)와 하입 기록 화면(전체)이 공유한다.
struct HypeCollection: View {
    @Environment(AppSession.self) private var appSession
    @Binding var items: [API.HypeItem]
    /// nil이면 전체, 값이 있으면 최근 N개 날짜 그룹만 렌더링(미리보기).
    var maxGroups: Int? = nil
    /// 마지막 그룹이 보이면 호출(페이지네이션). maxGroups가 있으면 호출 안 함.
    var onReachEnd: (() async -> Void)? = nil
    /// 하입 제거가 하드 실패해 목록 재동기화가 필요할 때 호출.
    var onReloadNeeded: (() async -> Void)? = nil

    @State private var audio = FeedAudioController()
    @State private var detailTarget: DetailTarget?
    @State private var actionTarget: API.HypeItem?

    private struct DetailTarget: Identifiable { let id: Int }

    private struct DateGroup: Identifiable {
        let id: Date          // startOfDay
        let title: String
        let tracks: [API.HypeItem]
    }

    /// 백엔드가 최신순으로 주므로 등장 순서를 유지해 날짜별로 묶는다.
    private var groups: [DateGroup] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [API.HypeItem]] = [:]
        for item in items {
            let day = cal.startOfDay(for: item.hypedAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        let all = order.map { DateGroup(id: $0, title: $0.formatted(date: .long, time: .omitted), tracks: buckets[$0] ?? []) }
        if let maxGroups { return Array(all.prefix(maxGroups)) }
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(group.tracks, id: \.userHypeTrackId) { track in
                                cell(track)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
                .onAppear {
                    guard maxGroups == nil, group.id == groups.last?.id else { return }
                    Task { await onReachEnd?() }
                }
            }
        }
        .onDisappear { audio.stop() }
        // 피드 등 다른 화면에서 하입이 풀리면 이 목록에서도 제거.
        .onChange(of: appSession.hypeState) { _, state in
            items.removeAll { state[$0.trackId] == false }
        }
        .sheet(item: $detailTarget) { TrackDetailView(trackId: $0.id) }
        .sheet(item: $actionTarget) { track in
            actionSheet(track)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
    }

    private func cell(_ track: API.HypeItem) -> some View {
        let isPlaying = audio.activeTrackId == track.trackId && !audio.isPaused
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: track.artworkUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSColor.surface
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                if isPlaying {
                    ZStack {
                        Color.black.opacity(0.3)
                        Image(systemName: "pause.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            Text(track.trackName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            Text(track.artistName)
                .font(.system(size: 10))
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onTapGesture { playPreview(track) }
        .onLongPressGesture { actionTarget = track }
    }

    /// 하입 트랙 롱프레스 모달 — 상세 보기 / 하입 제거.
    private func actionSheet(_ track: API.HypeItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: track.artworkUrl)) { $0.resizable().scaledToFill() }
                    placeholder: { DSColor.surface }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.trackName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: 13))
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            Button {
                let id = track.trackId
                actionTarget = nil
                // 시트가 닫힌 뒤 상세 시트를 띄운다(같은 앵커에서 시트 중첩 방지).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    detailTarget = DetailTarget(id: id)
                }
            } label: {
                actionRow("Track details", systemName: "info.circle")
            }
            Divider().padding(.leading, 20)
            Button {
                removeHype(track)
                actionTarget = nil
            } label: {
                actionRow("Remove hype", systemName: "heart.slash", destructive: true)
            }
        }
        .buttonStyle(.plain)
        .presentationBackground(.white)
    }

    private func actionRow(_ label: LocalizedStringKey, systemName: String, destructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 17))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 16))
            Spacer()
        }
        .foregroundStyle(destructive ? DSColor.destructive : DSColor.textPrimary)
        .padding(.horizontal, 20)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private func playPreview(_ track: API.HypeItem) {
        guard let url = URL(string: track.previewUrl) else { return }
        audio.togglePreview(trackId: track.trackId, url: url)
    }

    private func removeHype(_ track: API.HypeItem) {
        items.removeAll { $0.trackId == track.trackId }   // 낙관적 제거.
        if audio.activeTrackId == track.trackId { audio.stop() }
        appSession.hypeState[track.trackId] = false       // 피드 등 다른 화면에 반영.
        Task {
            do { try await appSession.api.send(.unhype(trackId: track.trackId)) }
            catch APIError.server(_, _, let status) where status == 404 { }   // 이미 없음.
            catch { await onReloadNeeded?() }             // 실패 시 목록 재동기화.
        }
    }
}

// 롱프레스 모달 표시용. userHypeTrackId는 목록 내 고유값.
extension API.HypeItem: Identifiable {
    public var id: Int { userHypeTrackId }
}
