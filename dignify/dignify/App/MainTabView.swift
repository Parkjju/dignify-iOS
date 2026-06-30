import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.makeContentView()
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(DSColor.brand)
    }
}

#Preview {
    MainTabView()
}
