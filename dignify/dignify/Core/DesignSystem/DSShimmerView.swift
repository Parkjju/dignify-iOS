import SwiftUI

struct DSShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            Color.white.opacity(0.14)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.30), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6)
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

#Preview {
    DSShimmerView()
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 24))
}
