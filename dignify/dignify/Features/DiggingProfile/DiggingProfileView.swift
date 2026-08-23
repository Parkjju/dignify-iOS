import SwiftUI

/// 마이페이지에서 진입하는 취향 유형 리포트. 게스트는 마이페이지 탭 자체가 막혀 여기 못 온다.
struct DiggingProfileView: View {
    /// rawValue가 그대로 `GET /users/me/stats`의 range 쿼리값.
    enum Range: String, CaseIterable { case week, all
        /// String으로 두면 Text가 번역을 안 타고 영어로 박힌다.
        var label: LocalizedStringKey { self == .week ? "This week" : "All time" }
    }

    @Environment(AppSession.self) private var appSession

    @State private var range: Range = .all
    @State private var shareImage: ShareImage?

    @State private var stats: DiggingStats?
    @State private var statsFailed = false
    /// 이미 받아온 range. `.task`는 화면에 다시 들어올 때마다 재실행되므로, 같은 range면 재요청하지 않는다.
    @State private var loadedRange: Range?

    // 크레이트(하입) 브라우징 — 마이페이지에서 이관. 실 API(GET /users/me/hypes).
    @State private var hypes: [API.HypeItem] = []
    @State private var hypeCursor: Int?
    @State private var hypesLoading = true
    @State private var hypesFailed = false
    /// 한 번 받아온 뒤엔 재진입해도 다시 안 받는다. 목록이 바뀌는 삭제 경로만 force로 갱신.
    @State private var hypesLoaded = false
    @State private var showAllHypes = false
    /// 프로필엔 최근 N일 미리보기만, 나머지는 See all → HypeHistoryView.
    /// 3일 = 최근 흐름은 보이되 스크롤이 길어지지 않는 선(전체는 See all).
    private let previewDayLimit = 3
    private let perDayPreviewLimit = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                rangeToggle
                if let stats {
                    statsSections(stats)
                } else if statsFailed {
                    statsError
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 80)
                }
                // 만든 것 → 모은 것 순. 픽이 없으면 이 뷰가 스스로 아무것도 안 그린다.
                MyPicksSection()
                crateSection
                if let stats, stats.isUnlocked { shareButton(stats) }
            }
            .padding(.vertical, 20)
        }
        .background(DSColor.background)
        .navigationTitle("Digging Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareImage) { ShareSheet(items: [ImageShareSource(image: $0.image)]) }
        .navigationDestination(isPresented: $showAllHypes) { HypeHistoryView() }
        .task(id: range) { await loadStats() }
        .task { await loadHypes() }
    }

    @ViewBuilder
    private func statsSections(_ stats: DiggingStats) -> some View {
        hero(stats)
        if let headline = stats.headline {
            Text(headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        volumePair(stats)
        lensBlock(title: "Top genres", dig: stats.listenedByGenre, keep: stats.hypedByGenre)
        lensBlock(title: "Top artists", dig: stats.listenedByArtist, keep: stats.hypedByArtist)
    }

    private var statsError: some View {
        VStack(spacing: 10) {
            Text("Couldn't load")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
            Button("Try again") { Task { await loadStats() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DSColor.brand)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    /// range 전환마다 재조회. 이전 range의 숫자가 잠깐이라도 새 라벨 아래 남지 않도록 먼저 비운다.
    /// 같은 range를 이미 받아왔으면(크레이트 전체보기에 다녀온 경우 등) 그대로 두고 재요청하지 않는다.
    /// 실패했을 땐 loadedRange를 안 채우므로 다시 들어오면 재시도된다.
    private func loadStats(force: Bool = false) async {
        if !force, loadedRange == range, stats != nil { return }
        stats = nil
        statsFailed = false
        do {
            let res = try await appSession.api.send(.myStats(range: range.rawValue), as: API.UserStats.self)
            stats = DiggingStats(res)
            loadedRange = range
        } catch {
            statsFailed = true
        }
    }

    // MARK: - Toggle

    private var rangeToggle: some View {
        Picker("", selection: $range) {
            ForEach(Range.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    // MARK: - Hero (type or lock)

    private func hero(_ stats: DiggingStats) -> some View {
        VStack(spacing: 8) {
            if let type = stats.type {
                Text("YOUR TYPE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.75))
                Text(type.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let g = stats.flavorGenre {
                    Text("deep in \(g)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(type.blurb)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Keep digging to unlock your type")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Dig 10 tracks and hype 3 to reveal it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            LinearGradient(colors: [DSColor.brand, Color(hex: 0x2A2350)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Volume pair

    private func volumePair(_ stats: DiggingStats) -> some View {
        HStack(spacing: 12) {
            // 세는 기준(5초·세션당 1회·피드 한정)이 숫자만 보고는 안 드러나서 여기만 안내를 붙인다.
            // 담은 트랙은 하입 버튼을 누른 결과라 설명이 필요 없다.
            StatBox(value: stats.distinctListenedCount, label: "tracks dug",
                    note: "Counted when you listen to a track for 5 seconds or more in the feed. Once per track each time you open the app.")
            StatBox(value: stats.hypeCount, label: "tracks kept")
        }
        .padding(.horizontal, 20)
    }

    private struct StatBox: View {
        let value: Int
        let label: LocalizedStringKey
        var note: LocalizedStringKey?

        @State private var showNote = false

        var body: some View {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DSColor.textPrimary)
                HStack(spacing: 4) {
                    Text(label)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    if note != nil {
                        Button { showNote = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(DSColor.textTertiary)
                                .padding(6)          // 아이콘이 작아 탭 영역만 넓힌다
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How this is counted")
                    }
                }
                .padding(.trailing, note != nil ? -6 : 0)   // 탭 영역 padding만큼 중앙이 밀리는 것 보정
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .popover(isPresented: $showNote) {
                if let note {
                    Text(note)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(width: 260)
                        // 아이폰에선 popover가 시트로 바뀌는 게 기본이라, 말풍선으로 고정한다.
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    // MARK: - Two-lens block (dig / keep)

    /// 탐색(listened) vs 담음(hyped) 두 렌즈. 첫인상에 구분되도록 컬럼마다
    /// 고유 아이콘·색·배경을 준다 — explore=헤드폰/회색, keep=하입아이콘/브랜드.
    private enum Lens {
        case explore, keep
        var caption: LocalizedStringKey { self == .explore ? "You explore" : "You keep" }
        var tint: Color { self == .explore ? DSColor.textSecondary : DSColor.brand }
        var bg: Color { self == .explore ? DSColor.surface : DSColor.brandLight }
    }

    private func lensBlock(title: LocalizedStringKey, dig: [DiggingStats.Count], keep: [DiggingStats.Count]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            HStack(alignment: .top, spacing: 12) {
                lensColumn(.explore, items: dig)
                lensColumn(.keep, items: keep)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func lensIcon(_ lens: Lens) -> some View {
        switch lens {
        case .explore:
            Image(systemName: "headphones")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(lens.tint)
        case .keep:
            Image("HypeIcon")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(lens.tint)
        }
    }

    private func lensColumn(_ lens: Lens, items: [DiggingStats.Count]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                lensIcon(lens)
                Text(lens.caption)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(lens.tint)
            }
            if items.isEmpty {
                Text("—").font(DSTypography.body).foregroundStyle(DSColor.textTertiary)
            } else {
                ForEach(items.prefix(5)) { item in
                    HStack {
                        Text(item.name)
                            .font(DSTypography.bodyMedium)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(item.count)")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(lens.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Crate (하입 브라우징 — 마이페이지에서 이관)

    /// 내 크레이트 = 하입한 트랙. 최근 N일 미리보기 + See all 전체 화면.
    /// 실 데이터/재생/제거/동기화는 HypeCollection이 담당(마이페이지와 공유).
    @ViewBuilder
    private var crateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 통계 → 만든 픽 → 담은 곡이 한 스크롤에 이어 붙어 어디까지가 뭔지 안 읽혔다.
            // 각 섹션이 자기 위의 구분선을 갖는다(`MyPicksSection`도 같은 규칙).
            Divider().padding(.horizontal, 20)
            Text("Your crate")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 20)
            if hypesLoading && hypes.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if hypes.isEmpty {
                Text(hypesFailed ? String(localized: "Couldn't load") : String(localized: "No hyped tracks yet"))
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                HypeCollection(items: $hypes,
                               maxGroups: previewDayLimit,
                               perDayLimit: perDayPreviewLimit,
                               onReloadNeeded: { await loadHypes(force: true) },
                               onSeeAll: hasMoreHypes ? { showAllHypes = true } : nil)
                if hasMoreHypes {
                    Button { showAllHypes = true } label: { seeAllRow }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var seeAllRow: some View {
        HStack {
            Text("See all hypes")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DSColor.brand)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.brand)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    private var hasMoreHypes: Bool {
        HypeGrouping.hasMore(hypes, cursor: hypeCursor,
                             maxGroups: previewDayLimit, perDayLimit: perDayPreviewLimit)
    }

    /// 최근 previewDayLimit일치가 완결될 때까지 페이지를 이어 받는다(마이페이지 로직 이관).
    /// 최대 8페이지라 재진입마다 다시 받으면 비싸다. 하입을 지운 뒤처럼 목록이 바뀐 경우만 force로 다시 받는다.
    private func loadHypes(force: Bool = false) async {
        if !force, hypesLoaded { return }
        hypesLoading = true
        hypesFailed = false
        do {
            var collected: [API.HypeItem] = []
            var cursor: Int? = nil
            let maxPages = 8
            for _ in 0..<maxPages {
                let res = try await appSession.api.send(.myHypes(cursor: cursor), as: API.HypeListResponse.self)
                collected.append(contentsOf: res.items)
                cursor = res.nextCursor
                let days = Set(collected.map { Calendar.current.startOfDay(for: $0.hypedAt) }).count
                if cursor == nil || days > previewDayLimit { break }
            }
            hypes = collected
            hypeCursor = cursor
            hypesLoaded = true
        } catch {
            hypesFailed = true
        }
        hypesLoading = false
    }

    // MARK: - Share

    private func shareButton(_ stats: DiggingStats) -> some View {
        Button {
            if let img = ProfileShareCard.render(stats: stats) {
                shareImage = ShareImage(image: img)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share my taste")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(DSColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

/// UIImage를 .sheet(item:)로 실어보내기 위한 Identifiable 래퍼.
#Preview {
    NavigationStack { DiggingProfileView() }
        .environment(AppSession())
}
