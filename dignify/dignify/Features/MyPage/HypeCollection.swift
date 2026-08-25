import SwiftUI
import PostHog

/// 하입 트랙을 날짜(일 단위)별 가로 스크롤로 렌더링하는 재사용 컴포넌트.
/// 셀 탭 재생 / 롱프레스 액션시트(상세·제거) / 끝 도달 시 페이지네이션 트리거를 포함한다.
/// 마이페이지(최근 N일 미리보기)와 하입 기록 화면(전체)이 공유한다.
struct HypeCollection: View {
    @Environment(AppSession.self) private var appSession
    @Binding var items: [API.HypeItem]
    /// nil이면 전체, 값이 있으면 최근 N개 날짜 그룹만 렌더링(미리보기).
    var maxGroups: Int? = nil
    /// nil이면 날짜당 전체, 값이 있으면 그 날짜의 앞 N개만(미리보기 가로 목록).
    var perDayLimit: Int? = nil
    /// 마지막 그룹이 보이면 호출(페이지네이션). maxGroups가 있으면 호출 안 함.
    var onReachEnd: (() async -> Void)? = nil
    /// 하입 제거가 하드 실패해 목록 재동기화가 필요할 때 호출.
    var onReloadNeeded: (() async -> Void)? = nil
    /// 미리보기에서 날짜 행 끝을 오른쪽으로 당기거나 See all 셀을 탭하면 호출(전체 화면 이동).
    var onSeeAll: (() -> Void)? = nil
    /// 선택 모드. 값이 있으면 **편집 모드보다 우선하고** 탭이 선택 토글이 된다(시드 고르기).
    /// 셋을 한 컴포넌트에 두는 이유는 날짜 그룹·페이지네이션·썸네일 셀을 그대로 쓰기 위해서다.
    var selection: Binding<Set<Int>>? = nil
    /// 선택 모드에서 고를 수 있는 최대 개수. 서버의 MoodRecommender.SEEDS와 같아야 한다.
    var selectionLimit: Int = 5
    /// 선택 모드에서 **첫 셀에 코치마크 앵커를 단다.** 유저마다 담은 곡이 달라 셀의 위치와
    /// 날짜 묶음 수가 제각각이라, 좌표를 적어 두면 누구에게도 안 맞는다. 앵커는 레이아웃이
    /// 끝난 뒤의 실측이라 목록이 어떻게 생겼든 첫 셀 위에 정확히 앉는다.
    var coachAnchors: Bool = false
    /// 편집 모드. 켜지면 셀마다 제거 배지가 붙고 탭이 재생 대신 제거로 바뀐다.
    /// 롱프레스는 이 컴포넌트를 처음 쓰는 사람에게 보이지 않아서, 제거하는 길을 눈에 보이게 하나 더 둔다.
    /// 소유는 화면 쪽이다 — 편집 버튼이 네비게이션 바나 섹션 헤더에 서야 하는데 둘 다 이 뷰 바깥이다.
    var isEditing: Bool = false

    @State private var audio = FeedAudioController()
    @State private var detailTarget: DetailTarget?
    @State private var actionTarget: API.HypeItem?
    /// 편집 모드에서 제거를 누른 곡. 확인 알럿이 뜬 뒤에야 실제로 지운다.
    @State private var removeTarget: API.HypeItem?

    private struct DetailTarget: Identifiable { let id: Int }

    private var groups: [HypeGrouping.DayGroup] {
        HypeGrouping.dayGroups(items, maxGroups: maxGroups, perDayLimit: perDayLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                DayRow(group: group, onSeeAll: onSeeAll) { track in
                    cell(track)
                }
                .padding(.bottom, 20)
            }
        }
        .onDisappear { audio.stop() }
        // 피드 등 다른 화면에서 하입이 풀리면 이 목록에서도 제거.
        .onChange(of: appSession.hypeState) { _, state in
            withAnimation(.easeInOut(duration: 0.2)) {
                items.removeAll { state[$0.trackId] == false }
            }
        }
        .sheet(item: $detailTarget) { TrackDetailView(trackId: $0.id) }
        .sheet(item: $actionTarget) { track in
            actionSheet(track)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        // 편집 모드에선 셀 전체가 표적이라 스크롤하다 스친 손가락에도 곡이 빠진다.
        // 롱프레스 액션시트에서 온 제거는 안 묻는다 — 거긴 이미 "하입 제거"를 직접 고른 자리다.
        .alert("Remove this track?", isPresented: removeBinding, presenting: removeTarget) { track in
            Button("Remove hype", role: .destructive) { removeHype(track) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can hype it again anytime.")
        }
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })
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
        .overlay(alignment: .topLeading) {
            if let selection {
                selectionBadge(isOn: selection.wrappedValue.contains(track.trackId))
            } else if isEditing {
                removeBadge
            }
        }
        .contentShape(Rectangle())
        // 배지만 눌러 지우게 하면 표적이 20pt라 자꾸 빗나간다. 편집 모드에선 셀 전체가 제거다.
        .onTapGesture {
            if let selection {
                toggleSelection(track, selection)
            } else if isEditing {
                removeTarget = track
            } else {
                playPreview(track)
            }
        }
        .onLongPressGesture { if !isEditing && selection == nil { actionTarget = track } }
        // 페이지네이션 트리거는 날짜 그룹이 아니라 **마지막 셀**에 건다.
        // 그룹 id는 startOfDay라 새 페이지 10개가 전부 같은 날이면 id가 그대로 →
        // onAppear가 다시 안 불려 그 뒤 하입이 영영 안 보였다.
        .onAppear {
            guard maxGroups == nil, track.userHypeTrackId == HypeGrouping.pagingAnchor(items) else { return }
            Task { await onReachEnd?() }
        }
        .coachAnchor(coachAnchors && track.userHypeTrackId == items.first?.userHypeTrackId ? .seedCell : nil)
    }

    /// 날짜 한 줄(가로 스크롤). onSeeAll이 있으면(미리보기) 끝에 See all 셀을 붙이고,
    /// 오른쪽 끝을 임계 이상 당겼다 놓으면 전체 화면으로 넘긴다. 셀 탭으로도 이동 가능.
    private struct DayRow<Cell: View>: View {
        let group: HypeGrouping.DayGroup
        let onSeeAll: (() -> Void)?
        @ViewBuilder let cell: (API.HypeItem) -> Cell

        /// 당긴 만큼(리빌 애니메이션용)과 드래그 중 최대 오버스크롤(놓을 때 판정용).
        @State private var reveal: CGFloat = 0
        @State private var peak: CGFloat = 0
        /// 트랙 셀들의 실제 너비 / 스크롤 뷰포트 너비 — 넘치는지 판정용.
        @State private var tracksWidth: CGFloat = 0
        @State private var containerWidth: CGFloat = 0
        private let threshold: CGFloat = 64
        private let hPadding: CGFloat = 20

        /// 트랙들이 좌우 패딩 포함해 뷰포트 안에 다 들어오면 스크롤할 게 없다.
        private var fits: Bool {
            tracksWidth > 0 && containerWidth > 0 && tracksWidth <= containerWidth - hPadding * 2
        }
        /// 미리보기(onSeeAll 있음)이고 넘칠 때만 See all 셀·제스처를 노출.
        private var showsSeeAll: Bool { onSeeAll != nil && !fits }
        /// 당김 리빌은 iOS 18 스크롤 관측 API가 있어야 한다. 그 아래선 See all 셀 탭이 유일한 경로.
        private var revealsByOverscroll: Bool { if #available(iOS 18.0, *) { true } else { false } }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, hPadding)
                scroller
            }
        }

        @ViewBuilder
        private var scroller: some View {
            let base = ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(group.tracks, id: \.userHypeTrackId) { cell($0) }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tracksWidth = $0 }
                    if showsSeeAll { seeAllCell }
                }
                .padding(.horizontal, hPadding)
                // 배지가 셀 위로 6pt 삐져나오는데 offset은 레이아웃 크기를 안 늘린다 →
                // 콘텐츠 높이가 셀 높이 그대로라 ScrollView가 배지 윗부분을 잘라낸다.
                // 여기서 자리를 만들고 위 VStack 간격을 8에서 2로 줄여 날짜와의 간격은 유지한다.
                .padding(.top, 6)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .scrollDisabled(fits)
            .scrollBounceBehavior(.always, axes: .horizontal)

            if #available(iOS 18.0, *) {
                base
                    .onScrollGeometryChange(for: CGFloat.self) { g in
                        // 오른쪽 끝을 넘어간 오버스크롤 양(0 이상).
                        max(0, g.contentOffset.x + g.containerSize.width - g.contentSize.width)
                    } action: { _, v in
                        guard showsSeeAll else { return }
                        reveal = v
                        peak = max(peak, v)
                    }
                    .onScrollPhaseChange { oldPhase, newPhase, _ in
                        guard showsSeeAll else { return }
                        if newPhase == .interacting { peak = 0; return }
                        // 손을 뗀 순간(드래그 종료) 최대 당김이 임계를 넘었으면 이동.
                        if oldPhase == .interacting, peak > threshold {
                            peak = 0
                            onSeeAll?()
                        }
                    }
            } else {
                base
            }
        }

        private var seeAllCell: some View {
            VStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .offset(x: min(reveal, threshold) * 0.25)
                Text("See all")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(DSColor.brand)
            .opacity(revealsByOverscroll ? min(1, 0.4 + reveal / threshold) : 1)
            .frame(width: 56, height: 72)
            .contentShape(Rectangle())
            .onTapGesture { onSeeAll?() }
        }
    }

    /// 편집 모드 배지. 아트워크 좌상단 모서리에 반쯤 걸치게 띄운다 —
    /// 안쪽에 넣으면 72pt 썸네일에서 앨범 아트를 가리고, 완전히 바깥에 두면 잘린다.
    private var removeBadge: some View {
        Image(systemName: "minus.circle.fill")
            .font(.system(size: 20))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, DSColor.destructive)
            .offset(x: -6, y: -6)
            .allowsHitTesting(false)   // 탭은 셀 전체가 받는다.
    }

    /// 선택 모드 배지. 고른 것은 브랜드색 원에 흰 체크, 안 고른 것은 **흰 원에 회색 테두리**다.
    /// 빈 원이 없으면 여기서 무엇을 할 수 있는지가 안 보여서 유저가 그냥 재생인 줄 안다.
    ///
    /// 테두리를 흰색으로 두면 배지가 아트워크 밖으로 나간 절반이 밝은 지면에 묻혀서 원이
    /// 잘린 것처럼 보인다. 아트워크와 지면 양쪽에서 다 읽히려면 **면은 흰색, 선은 회색**이어야 한다.
    private func selectionBadge(isOn: Bool) -> some View {
        Circle()
            .fill(isOn ? DSColor.brand : .white)
            .frame(width: 20, height: 20)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(DSColor.textTertiary, lineWidth: 1.5)
                }
            }
            .offset(x: -6, y: -6)
            .allowsHitTesting(false)
    }

    /// 상한을 넘으면 **아무 일도 일어나지 않는다.** 가장 오래 고른 것을 밀어내면 방금 무엇이
    /// 빠졌는지 화면에서 안 보이고, 유저는 자기가 고른 곡이 사라진 줄 안다.
    private func toggleSelection(_ track: API.HypeItem, _ selection: Binding<Set<Int>>) {
        if selection.wrappedValue.contains(track.trackId) {
            selection.wrappedValue.remove(track.trackId)
        } else if selection.wrappedValue.count < selectionLimit {
            selection.wrappedValue.insert(track.trackId)
        }
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
        // 편집 버튼이 롱프레스를 대신하는지 보려면 어느 길로 들어왔는지가 필요하다.
        PostHogSDK.shared.capture("hype_removed",
                                  properties: ["via": isEditing ? "edit" : "long_press"])
        // 애니메이션 없이 지우면 옆 곡들이 순간이동해서 무엇이 빠졌는지가 안 읽힌다.
        withAnimation(.easeInOut(duration: 0.2)) {
            items.removeAll { $0.trackId == track.trackId }   // 낙관적 제거.
        }
        if audio.activeTrackId == track.trackId { audio.stop() }
        appSession.hypeState[track.trackId] = false       // 피드 등 다른 화면에 반영.
        Task {
            do { try await appSession.api.send(.unhype(trackId: track.trackId)) }
            catch APIError.server(_, _, let status) where status == 404 { }   // 이미 없음.
            catch {
                await onReloadNeeded?()                   // 실패 시 목록 재동기화.
                return
            }
            // 디깅 프로필의 통계는 하입 수에서 나온다. 서버에서 빠진 뒤에 알린다.
            appSession.hypeChangeToken += 1
        }
    }
}

// 롱프레스 모달 표시용. userHypeTrackId는 목록 내 고유값.
extension API.HypeItem: Identifiable {
    public var id: Int { userHypeTrackId }
}
