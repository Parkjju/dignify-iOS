import Foundation

/// 하입 목록의 그룹핑·페이지네이션 규칙. 뷰에서 떼어 낸 이유는 조용히 틀리는 부류라서다 —
/// 화면은 멀쩡한데 다음 페이지가 안 불려 하입이 사라진 채로 몇 릴리즈를 갔다(1.0.9에서 수정).
enum HypeGrouping {
    struct DayGroup: Identifiable {
        let id: Date                   // startOfDay
        let tracks: [API.HypeItem]
        var title: String { id.formatted(date: .long, time: .omitted) }
    }

    /// 백엔드가 최신순으로 주므로 등장 순서를 유지해 날짜별로 묶는다.
    /// - maxGroups: 최근 N일 그룹만(미리보기). nil이면 전체.
    /// - perDayLimit: 날짜당 앞 N개만. nil이면 전체.
    static func dayGroups(_ items: [API.HypeItem],
                          maxGroups: Int? = nil,
                          perDayLimit: Int? = nil,
                          calendar: Calendar = .current) -> [DayGroup] {
        var order: [Date] = []
        var buckets: [Date: [API.HypeItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.hypedAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        let all = order.map { day -> DayGroup in
            var tracks = buckets[day] ?? []
            if let perDayLimit { tracks = Array(tracks.prefix(perDayLimit)) }
            return DayGroup(id: day, tracks: tracks)
        }
        if let maxGroups { return Array(all.prefix(maxGroups)) }
        return all
    }

    /// 다음 페이지 트리거가 물어야 할 기준값 — **마지막 트랙**이지 마지막 날짜 그룹이 아니다.
    /// 그룹 id는 startOfDay라 새 페이지가 전부 같은 날이면 값이 그대로고, 그러면
    /// SwiftUI가 뷰를 재사용해 onAppear를 다시 안 불러 페이지네이션이 죽는다.
    static func pagingAnchor(_ items: [API.HypeItem]) -> Int? {
        items.last?.userHypeTrackId
    }

    /// 미리보기 밖에 더 볼 하입이 있는가 — 다음 페이지 존재 / 날짜 초과 / 특정 날짜 트랙 초과.
    static func hasMore(_ items: [API.HypeItem],
                        cursor: Int?,
                        maxGroups: Int,
                        perDayLimit: Int,
                        calendar: Calendar = .current) -> Bool {
        if cursor != nil { return true }
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.hypedAt) }
        if byDay.count > maxGroups { return true }
        return byDay.values.contains { $0.count > perDayLimit }
    }
}
