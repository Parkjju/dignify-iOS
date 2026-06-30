import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case feed
    case myPage

    var id: String { rawValue }

    @ViewBuilder
    func makeContentView() -> some View {
        switch self {
        case .feed:
            FeedView()
        case .myPage:
            MyPageView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .feed:
            Label("Feed", systemImage: "house.fill")
        case .myPage:
            Label("My", systemImage: "person.crop.circle.fill")
        }
    }
}
