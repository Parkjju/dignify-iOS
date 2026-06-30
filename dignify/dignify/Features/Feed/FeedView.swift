import SwiftUI

struct FeedView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColor.surface, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                RoundedRectangle(cornerRadius: DSRadius.extraLarge)
                    .fill(DSColor.brand.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(DSColor.brand)
                    }

                VStack(spacing: 8) {
                    Text("Feed starts here")
                        .font(DSTypography.title)
                        .foregroundStyle(DSColor.textPrimary)

                    Text("Swipeable music previews arrive in Phase 4.")
                        .font(DSTypography.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(24)
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}
