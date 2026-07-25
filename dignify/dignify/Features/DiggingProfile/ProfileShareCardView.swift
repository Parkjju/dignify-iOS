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
            background
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
                    cardStat(listenedCount, "tracks dug")
                    cardStat(hypeCount, "tracks kept")
                }
                .padding(.top, 32)
                Spacer()
                footer.padding(.bottom, 44)
            }
            .padding(.horizontal, 36)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// label은 LocalizedStringKey — String으로 받으면 번역을 안 타고 영어로 박힌다.
    /// 키는 프로필 화면(`tracks dug` / `tracks kept`)과 공유해서 카드와 화면 문구가 갈리지 않게 한다.
    private func cardStat(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Background

    /// 단색 그라디언트 한 장은 밋밋해서 세 겹으로 쌓는다: 대각 베이스 + 빛 번짐 두 개 + 레코드 홈.
    /// ImageRenderer는 blur/Material을 제대로 안 그리는 경우가 있어, 번짐은 RadialGradient로 만든다.
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1A1340), DSColor.brand, Color(hex: 0x140F30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            RadialGradient(colors: [Color(hex: 0x8B7BFF).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.12, y: 0.08), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0xFF5C9B).opacity(0.32), .clear],
                           center: UnitPoint(x: 0.95, y: 0.92), startRadius: 0, endRadius: 300)

            grooves

            // 아래쪽을 살짝 눌러 푸터 글자가 배경에 묻히지 않게.
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
        }
    }

    /// 레코드 홈 모티프 — 디깅=판 파기. 중앙 텍스트를 안 가리도록 오른쪽 아래로 밀어 일부만 걸치게 둔다.
    private var grooves: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.055), lineWidth: 1)
                    .frame(width: 200 + CGFloat(i) * 66)
            }
        }
        .offset(x: 150, y: 235)
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
