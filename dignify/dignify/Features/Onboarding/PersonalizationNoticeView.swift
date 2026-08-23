import SwiftUI

/// 하입이 이미 쌓인 유저에게 **개인화가 켜졌다는 사실만** 알린다.
///
/// 이 사람들은 라운드를 태우면 안 된다. 시드가 최근 하입 5개라(`MoodRecommender.SEEDS`)
/// 라운드에서 고른 3곡이 다섯 칸 중 셋을 차지해 버리고, 그러면 원래 취향으로 돌던 피드가
/// 갑자기 낯설어진다 — 개선이 아니라 고장으로 읽힌다. 그쪽은 이미 하입으로 시드가 있으니
/// 업데이트 직후부터 개인화된 피드를 그대로 받는다. 설명만 있으면 된다.
struct PersonalizationNoticeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image("HypeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text("Your feed follows your hypes now")
                    .font(DSTypography.title1)
                    .tracking(-0.48)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("The tracks you hyped decide what comes next — same sound, same mood. Hype something new and the feed turns with it.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Text("Nothing to set up. Genre settings are gone — the feed reads your hypes instead.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 16)
            Spacer()

            Button { onDismiss() } label: { Text("Got it") }
                .buttonStyle(DSPrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(DSColor.background)
    }
}
