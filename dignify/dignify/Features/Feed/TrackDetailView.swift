//
//  TrackDetailView.swift
//  dignify
//
//  트랙 상세 바텀시트. GET /tracks/{id} → 메타데이터 + 먼저 하입한 유저 최대 5명.
//  피드 카드의 상세 버튼에서 sheet(item:)로 제시.
//

import SwiftUI

struct TrackDetailView: View {
    let trackId: Int
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var detail: API.TrackDetail?
    @State private var loadFailed = false
    /// 콘텐츠 실측 높이로 시트를 딱 맞춘다(측정 전 추정치). 하입 영역이 5행 고정이라
    /// 트랙별 하입 수와 무관하게 높이가 일정 → 여백/리사이즈 없음.
    @State private var sheetHeight: CGFloat = 470

    var body: some View {
        Group {
            if let detail {
                loaded(detail)
            } else if loadFailed {
                failure
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.white)   // 기본 시트가 반투명하게 비쳐 뒤 피드가 보이던 문제 해결.
        .task { await load() }
    }

    private func load() async {
        do {
            detail = try await session.api.send(.trackDetail(id: trackId), as: API.TrackDetail.self)
        } catch {
            loadFailed = true
        }
    }

    private var failure: some View {
        VStack(spacing: 12) {
            Text("Couldn't load track info")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            Button("Try again") { loadFailed = false; Task { await load() } }
                .foregroundStyle(DSColor.brand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loaded(_ d: API.TrackDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(d)
            Divider().padding(.vertical, 20)
            hypers(d.firstHypers)
            actions(d)
                .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(GeometryReader { geo in   // 콘텐츠 실측 → 시트 높이.
            Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(SheetHeightKey.self) { sheetHeight = $0 }
    }

    private func header(_ d: API.TrackDetail) -> some View {
        HStack(spacing: 16) {
            AsyncImage(url: d.artworkUrl.itunesArtworkURL(size: 200)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DSShimmerView()
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text(d.trackName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(d.artistName)
                    .font(.system(size: 15))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                Text(d.collectionName)
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    badge(d.genreName)
                    badge(d.releaseDate.prefix(10).replacingOccurrences(of: "-", with: "."))
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(DSColor.borderLight, lineWidth: 1))
    }

    @ViewBuilder
    private func hypers(_ users: [API.UserSummary]) -> some View {
        Text("Hyped by")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DSColor.textTertiary)
            .padding(.bottom, 14)
        Group {
            if users.isEmpty {
                Text("No hypes yet")
                    .font(.system(size: 14))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(users, id: \.userId) { user in
                        HStack {
                            Text("@\(user.nickname)")
                                .font(.system(size: 14))
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            if let date = user.hypedAt {
                                Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                                    .font(.system(size: 13))
                                    .foregroundStyle(DSColor.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        // 5행 고정 예약(14pt 행 ~17 + 간격 16 → 5*17+4*16≈149). 하입 수와 무관하게 높이 일정.
        .frame(height: 149, alignment: .top)
    }

    private func actions(_ d: API.TrackDetail) -> some View {
        Button {
            if let url = URL(string: d.trackViewUrl) { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                Text("Listen on Apple Music")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 470
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
