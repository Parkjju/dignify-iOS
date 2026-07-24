import SwiftUI

/// 취향 유형 공유 카드 (9:16). 아트워크가 없어 원격 로드 불필요 → 동기 렌더.
/// ShareCardView와 크기/푸터 톤을 맞추되, 내용은 정체성(유형+볼륨+격차)만 담는다.
struct ProfileShareCardView: View {
    let typeName: String
    let flavor: String?
    let headline: String?
    let listenedCount: Int
    let hypeCount: Int

    static let size = CGSize(width: 360, height: 640)   // scale 3 → 1080×1920

    var body: some View {
        ZStack {
            LinearGradient(colors: [DSColor.brand, Color(hex: 0x2A2350)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Text("MY DIGGING TYPE")
                    .font(.system(size: 13, weight: .bold)).tracking(5)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 56)
                Spacer()
                Text(typeName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let flavor {
                    Text("deep in \(flavor)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 8)
                }
                if let headline {
                    Text(headline)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 8)
                }
                HStack(spacing: 40) {
                    cardStat(listenedCount, "dug")
                    cardStat(hypeCount, "kept")
                }
                .padding(.top, 32)
                Spacer()
                footer.padding(.bottom, 44)
            }
            .padding(.horizontal, 36)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func cardStat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                DSBrandMark(size: 22)
                Text("dignify").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            }
            Text("dig deeper").font(.system(size: 13, weight: .medium)).tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

enum ProfileShareCard {
    @MainActor
    static func render(stats: DiggingStats) -> UIImage? {
        guard let type = stats.type else { return nil }
        let renderer = ImageRenderer(content: ProfileShareCardView(
            typeName: type.name, flavor: stats.flavorGenre, headline: stats.headline,
            listenedCount: stats.distinctListenedCount, hypeCount: stats.hypeCount
        ))
        renderer.scale = 3
        return renderer.uiImage
    }
}
