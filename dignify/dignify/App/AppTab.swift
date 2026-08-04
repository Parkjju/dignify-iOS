import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case feed
    case picks
    case myPage

    var id: String { rawValue }

    @ViewBuilder
    func makeContentView() -> some View {
        switch self {
        case .feed:
            FeedView()
        case .picks:
            PickListView()
        case .myPage:
            MyPageView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .feed:
            Label("Feed", systemImage: "house.fill")
        case .picks:
            Label("Picks", systemImage: "square.stack.fill")
        case .myPage:
            Label("My", systemImage: "person.crop.circle.fill")
        }
    }
}
