import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                DSBrandMark(size: 64)
                Text("Dignify")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.96)
                    .foregroundStyle(DSColor.brand)
                Text("인디 음악을 발굴하고 당신만의 취향을 쌓아가세요.")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
            VStack(spacing: 12) {
                Button("Sign In With Apple", systemImage: "apple.logo") {

                }
                .buttonStyle(DSAppleSignInButtonStyle())
                Text("계속 진행하면 이용약관 및 개인정보처리방침에 동의하는 것으로 간주됩니다.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .padding(.bottom, 40)
        .background(DSColor.background)
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppSession())
}
