import SwiftUI

/// 차단 해제 화면. 차단 자체가 로컬 저장(서버 0)이라 여기가 유일한 되돌리기 경로다.
struct BlockedUsersView: View {
    @AppStorage(LocalModeration.blockedKey) private var blockedRaw = ""

    private var blocked: [String] { LocalModeration.items(blockedRaw) }

    var body: some View {
        Group {
            if blocked.isEmpty {
                Text("You haven't blocked anyone.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.background)
            } else {
                List {
                    ForEach(blocked, id: \.self) { nickname in
                        Text(verbatim: "@\(nickname)")
                            .font(.system(size: 15))
                            .foregroundStyle(DSColor.textPrimary)
                            .swipeActions {
                                Button("Unblock") {
                                    blockedRaw = LocalModeration.removing(nickname, from: blockedRaw)
                                }
                                .tint(DSColor.brand)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack { BlockedUsersView() }
}
#endif
