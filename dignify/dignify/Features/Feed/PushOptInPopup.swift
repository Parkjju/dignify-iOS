import SwiftUI

/// 특집 세트 완주 직후 띄우는 푸시 권한 안내 팝업.
///
/// iOS는 설치당 시스템 팝업을 한 번만 띄워준다. 맥락 없이 그 한 번을 쓰면 거부당했을 때
/// 되돌릴 방법이 없으므로, 먼저 이 팝업에서 물어보고 "알림 받기"를 누른 사람에게만
/// 시스템 팝업을 넘긴다. 거절은 아무것도 호출하지 않아 authorizationStatus가
/// .notDetermined로 남고, 하입 시점(FeedView)에서 다시 기회가 있다.
///
/// 시스템 알럿을 안 쓰는 이유는 톤이다. 회색 iOS 크롬은 오류/시스템 요구처럼 읽혀서
/// "저희가 직접 판 거예요"라는 문구와 싸운다. 다만 **iOS 알럿처럼 보이게 만들면 안 된다** —
/// 바로 뒤에 진짜 시스템 팝업이 오는 구조라, 회색 룩을 흉내 내면 가짜 시스템 다이얼로그가
/// 된다. 브랜드 컬러·우리 타이포로 명백히 우리 것임을 드러내는 게 그 선을 지키는 방법.
struct PushOptInPopup: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            // 딤 탭 = 거절. 시스템 알럿이 공짜로 주던 동작이라 직접 붙인다.
            // contentShape로 히트테스트를 먹어야 뒤 피드의 스와이프로 새지 않는다.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDecline)

            card
                .padding(.horizontal, 32)
        }
        // 팝업이 뜬 동안 VoiceOver 포커스가 뒤 피드로 새지 않게 가둔다.
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: 14) {
            DSBrandMark(size: 44)
                .padding(.bottom, 2)

            Text("This week's set, all done")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Those were dug up by us, by hand. We do it again every week — want a heads-up when the next one drops?")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 4)

            Button("Notify me", action: onAccept)
                .buttonStyle(DSPrimaryButtonStyle())

            Button("Not now", action: onDecline)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textTertiary)
                .padding(.top, 2)
        }
        // 고정 높이를 주지 않는다 — Dynamic Type을 키우면 카드가 같이 자라야 한다.
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.large))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
}

#Preview {
    ZStack {
        Color.gray
        PushOptInPopup(onAccept: {}, onDecline: {})
    }
}
