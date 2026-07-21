import SwiftUI

/// 로그인 직후 1회 보여주는 사용법 안내. 실제 UI를 가리키는 코치마크가 아니라
/// 풀스크린 카드 캐러셀. 재열람은 마이페이지에서 onFinish 없이 호출한다.
struct TutorialView: View {
    var onFinish: () -> Void

    @State private var index = 0

    private let pages = TutorialPage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if index < pages.count - 1 {
                    Button("Skip") { onFinish() }
                        .font(DSTypography.bodyMedium)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    TutorialPageView(page: page).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: index)

            PageDots(count: pages.count, index: index)
                .padding(.bottom, 24)

            Button {
                if index < pages.count - 1 {
                    withAnimation { index += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(index < pages.count - 1 ? "Next" : "Get started")
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(DSColor.background)
    }
}

private struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DSColor.brandLight)
                    .frame(width: 140, height: 140)
                page.icon
                    .foregroundStyle(DSColor.brand)
            }
            VStack(spacing: 12) {
                Text(page.title)
                    .font(DSTypography.title1)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? DSColor.brand : DSColor.borderLight)
                    .frame(width: i == index ? 20 : 8, height: 8)
                    .animation(.easeInOut, value: index)
            }
        }
    }
}

private struct TutorialPage: Identifiable {
    let id = UUID()
    let icon: AnyView
    let title: LocalizedStringKey
    let body: LocalizedStringKey

    static let all: [TutorialPage] = [
        TutorialPage(
            icon: symbol("hand.tap.fill"),
            title: "Double-tap to hype",
            body: "Love a track? Double-tap the card to hype it instantly."
        ),
        TutorialPage(
            icon: hypeIcon,
            title: "Or use the hype button",
            body: "Tap the hype button to save any track you like."
        ),
        TutorialPage(
            icon: symbol("opticaldisc"),
            title: "See track details",
            body: "Tap the disc icon to view full info and where to listen."
        ),
        TutorialPage(
            icon: symbol("hand.point.up.left.fill"),
            title: "Press and hold in My Page",
            body: "Long-press a track in My Page to open details or remove it."
        ),
        TutorialPage(
            icon: symbol("play.circle.fill"),
            title: "Play from My Page",
            body: "Tap any track in My Page to play its preview right there."
        ),
        TutorialPage(
            icon: symbol("person.crop.circle.badge.plus"),
            title: "Missing an artist?",
            body: "Search for them and tap Request — or add one from Artist Requests in My Page."
        ),
    ]

    private static func symbol(_ name: String) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: 56)))
    }

    private static var hypeIcon: AnyView {
        AnyView(
            Image("HypeIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
        )
    }
}

#Preview {
    TutorialView(onFinish: {})
}
