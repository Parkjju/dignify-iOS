import SwiftUI

struct MyPageView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(DSColor.brand)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("digger_preview")
                            .font(DSTypography.headline)
                            .foregroundStyle(DSColor.textPrimary)

                        Text("Profile setup starts in Phase 8.")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Library") {
                Label("Hyped Tracks", systemImage: "sparkles")
                Label("Genre Settings", systemImage: "slider.horizontal.3")
            }

            Section("Account") {
                Button("Log out") {
                    appSession.authState = .signedOut
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("My Page")
    }
}

#Preview {
    NavigationStack {
        MyPageView()
            .environment(AppSession())
    }
}
