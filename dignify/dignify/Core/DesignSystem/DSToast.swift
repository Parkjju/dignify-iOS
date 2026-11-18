import SwiftUI

/// 처리 결과 토스트(Components › Toast). 탭바 위 8, 3초 뒤 페이드 아웃, 누르는 동작 없음.
/// 띄우는 곳은 `AppSession.toast` 하나 — `MainTabView`가 그린다.
struct DSToastItem: Equatable {
    let id = UUID()
    let title: String
    var message: String?
}

struct DSToast: View {
    let item: DSToastItem
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(DSTypography.callout)
                .foregroundStyle(.white)
            if let message = item.message {
                Text(message)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textOnDarkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            // 블러 20 + #151719 85%. 머티리얼은 블러 반경을 못 정해 가장 얇은 것을 깐다.
            RoundedRectangle(cornerRadius: DSRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: DSRadius.medium).fill(DSColor.toastSurface))
        }
        .padding(.horizontal, 18)
        // 탭바(49) 위 8. `MainTabView` 오버레이는 기기 safe area 안이라 탭바 높이를 직접 더한다.
        .padding(.bottom, 49 + 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        // 같은 문구를 연달아 띄워도 3초를 새로 센다(id가 다르다).
        .task(id: item.id) {
            try? await Task.sleep(for: .seconds(3))
            onDone()
        }
        // 등장 0.2s 페이드 + 6 올라옴, 퇴장 0.3s 페이드. 동작 줄이기면 페이드만.
        // 띄우고 지우는 쪽은 withAnimation 없이 값만 바꾸면 된다.
        .transition(.asymmetric(
            insertion: (reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.2)),
            removal: .opacity.animation(.easeOut(duration: 0.3))))
    }
}
