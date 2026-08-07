import SwiftUI
import UIKit
import LinkPresentation

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
            // padding이 아니라 고정 frame. ImageRenderer는 폭 제안 없이 렌더할 수 있어
            // padding만 있으면 Text가 줄바꿈/말줄임 없이 카드 밖으로 잘린다.
            .frame(width: Self.size.width - 64)
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

    private var footer: some View { ShareCardFooter() }
}

/// 공유 카드 하단 브랜드 블록. 트랙 카드·픽 카드가 같이 쓴다 —
/// 카드마다 따로 그리면 폰트나 문구가 갈려서 같은 앱이 만든 것으로 안 읽힌다.
struct ShareCardFooter: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                DSBrandMark(size: 22)
                Text(verbatim: "dignify")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(verbatim: "dig deeper")
                .font(.system(size: 13, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

/// 공유 시트에 실을 렌더 완료 이미지. `.sheet(item:)`에 물리려고 id만 붙인 껍데기다.
struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
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

    /// 픽 카드도 같은 로더를 쓴다(캐시 우선). internal인 이유가 그것뿐이다.
    static func loadImage(_ url: URL?) async -> UIImage? {
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

/// 이미지 공유 시 상단 프리뷰에 제목(앱 이름)이 뜨게 하는 래퍼.
/// `UIImage`만 넘기면 iOS가 제목을 안 붙여 이름 칸이 비므로 LPLinkMetadata로 채운다.
final class ImageShareSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String? = nil) {
        self.image = image
        self.title = title
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "dignify"
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String { title }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)   // 프리뷰 썸네일 = 카드 이미지
        return metadata
    }
}
