import SwiftUI

/// 앱 팝업의 딤 + 카드 자리(디자인 `components/popup` 「띄우기·닫기 모션」).
/// 딤과 카드를 **따로** 움직인다 — 통째로 페이드하면 카드가 뜨는 순간이 안 읽힌다.
/// 등장: 딤 0.25s 페이드 · 카드 1.2 → 1 + 페이드(감속, 튕김 없음). 닫힘: 둘 다 0.2s 페이드, 크기 그대로.
///
/// 애니메이션이 transition 쪽에 붙어 있어서, 띄우는 쪽은 `withAnimation`으로 감싸기만 하면 된다.
struct DSPopupHost<Card: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let card: Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 딤 탭 = 닫기. 시스템 알럿이 공짜로 주던 동작이라 직접 붙인다.
            // contentShape로 히트테스트를 먹어야 뒤 화면의 스와이프로 새지 않는다.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25)),
                                        removal: Self.close))

            card
                .transition(.asymmetric(insertion: cardInsertion, removal: Self.close))
        }
        // 팝업이 뜬 동안 VoiceOver 포커스가 뒤 화면으로 새지 않게 가둔다.
        .accessibilityAddTraits(.isModal)
    }

    private static var close: AnyTransition { .opacity.animation(.easeOut(duration: 0.2)) }

    private var cardInsertion: AnyTransition {
        // 동작 줄이기면 크기 변화 없이 페이드만.
        let base: AnyTransition = reduceMotion ? .opacity : .scale(scale: 1.2).combined(with: .opacity)
        return base.animation(.spring(duration: 0.3, bounce: 0))
    }
}

/// 확인형 팝업 — 막힌 동작의 이유를 알린다. 브랜드마크·「나중에」 없이 제목·설명·확인 하나.
/// 비율은 알림 권유 팝업과 따로 둔다(Popup 명세 「확인 팝업」).
struct DSNoticePopup: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        DSPopupHost(onDismiss: onDismiss) {
            VStack(spacing: 0) {
                Text(title)
                    .font(DSTypography.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text(message)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, 6)
                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(DSColor.brand, in: RoundedRectangle(cornerRadius: DSRadius.medium))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .padding([.horizontal, .bottom], 20)
            .frame(width: 300)
            .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.large))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
    }
}
