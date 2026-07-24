import SwiftUI

/// 마이페이지에서 진입하는 취향 유형 리포트. 프로토타입은 목 데이터로 구동.
/// ponytail: 네트워크 미배선 — `stats(for:)`만 나중에 `GET /users/me/stats` 매핑으로 교체.
struct DiggingProfileView: View {
    enum Range: String, CaseIterable { case week, all
        var label: String { self == .week ? "This week" : "All time" }
    }

    @Environment(AppSession.self) private var appSession

    @State private var range: Range = .all
    @State private var shareImage: ShareImage?

    // 크레이트(하입) 브라우징 — 마이페이지에서 이관. 실 API(GET /users/me/hypes).
    @State private var hypes: [API.HypeItem] = []
    @State private var hypeCursor: Int?
    @State private var hypesLoading = true
    @State private var hypesFailed = false
    @State private var showAllHypes = false
    /// 프로필엔 최근 N일 미리보기만, 나머지는 See all → HypeHistoryView.
    /// 3일 = 최근 흐름은 보이되 스크롤이 길어지지 않는 선(전체는 See all).
    private let previewDayLimit = 3
    private let perDayPreviewLimit = 10

    private var stats: DiggingStats {
        range == .all ? .mockAllTime : .mockThisWeek
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                rangeToggle
                hero
                if let headline = stats.headline {
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                volumePair
                lensBlock(title: "Top genres", dig: stats.listenedByGenre, keep: stats.hypedByGenre)
                lensBlock(title: "Top artists", dig: stats.listenedByArtist, keep: stats.hypedByArtist)
                crateSection
                if stats.isUnlocked { shareButton }
            }
            .padding(.vertical, 20)
        }
        .background(DSColor.background)
        .navigationTitle("Digging Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareImage) { ShareSheet(items: [ImageShareSource(image: $0.image)]) }
        .navigationDestination(isPresented: $showAllHypes) { HypeHistoryView() }
        .task { await loadHypes() }
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

    private var hero: some View {
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

    private var volumePair: some View {
        HStack(spacing: 12) {
            stat(value: stats.distinctListenedCount, label: "tracks dug")
            stat(value: stats.hypeCount, label: "tracks kept")
        }
        .padding(.horizontal, 20)
    }

    private func stat(value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DSColor.textPrimary)
            Text(label)
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                               onReloadNeeded: { await loadHypes() },
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

    /// 미리보기 밖에 더 볼 하입이 있는가 — 날짜 초과 / 다음 페이지 존재 / 특정 날짜 트랙 초과.
    private var hasMoreHypes: Bool {
        if hypeCursor != nil { return true }
        let byDay = Dictionary(grouping: hypes) { Calendar.current.startOfDay(for: $0.hypedAt) }
        if byDay.count > previewDayLimit { return true }
        return byDay.values.contains { $0.count > perDayPreviewLimit }
    }

    /// 최근 previewDayLimit일치가 완결될 때까지 페이지를 이어 받는다(마이페이지 로직 이관).
    private func loadHypes() async {
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
        } catch {
            hypesFailed = true
        }
        hypesLoading = false
    }

    // MARK: - Share

    private var shareButton: some View {
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
private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview {
    NavigationStack { DiggingProfileView() }
        .environment(AppSession())
}
