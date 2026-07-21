import SwiftUI
import UIKit

/// SNS(인스타그램 스토리 등) 공유용 dignify 아이덴티티 카드. 9:16 비율.
/// ImageRenderer로 UIImage를 뽑아 공유 시트에 실어 보낸다. 아트워크는 원격 로드라
/// 렌더 전에 UIImage로 확보해 주입(빈 값이면 브랜드 그라디언트로 폴백).
struct ShareCardView: View {
    let artwork: UIImage?
    let trackName: String
    let artistName: String
    let genreName: String?

    // 논리 크기 360×640, 렌더 scale 3 → 1080×1920px.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                eyebrow
                    .padding(.top, 44)
                Spacer()
                artworkCard
                    .padding(.bottom, 28)
                Text(trackName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(artistName)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, 6)
                if let genreName {
                    Text(genreName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .padding(.top, 14)
                }
                Spacer()
                footer
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder
    private var background: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .blur(radius: 40)
                .overlay(Color.black.opacity(0.5))
        } else {
            LinearGradient(
                colors: [DSColor.brand, Color(hex: 0x2A2350)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var eyebrow: some View {
        Text("DIGGING")
            .font(.system(size: 13, weight: .bold))
            .tracking(5)
            .foregroundStyle(.white.opacity(0.9))
    }

    @ViewBuilder
    private var artworkCard: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
            } else {
                DSColor.brandLight
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        // 시그니처 하입 아이콘 배지 — 모서리에 걸쳐 앱 정체성을 드러낸다.
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle().fill(DSColor.brand)
                Image("HypeIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .offset(x: 12, y: -12)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                DSBrandMark(size: 22)
                Text("dignify")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("dig deeper")
                .font(.system(size: 13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

enum ShareCard {
    /// 아트워크를 UIImage로 확보(캐시 우선) 후 카드를 렌더해 반환.
    @MainActor
    static func render(trackName: String, artistName: String, genreName: String?, artworkURL: URL?) async -> UIImage? {
        let artwork = await loadImage(artworkURL)
        let renderer = ImageRenderer(
            content: ShareCardView(artwork: artwork, trackName: trackName, artistName: artistName, genreName: genreName)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    private static func loadImage(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let request = URLRequest(url: url)
        if let cached = URLCache.shared.cachedResponse(for: request), let img = UIImage(data: cached.data) {
            return img
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }
}

/// UIActivityViewController 래퍼. 인스타그램·메시지 등 설치된 SNS로 카드+링크 공유.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
