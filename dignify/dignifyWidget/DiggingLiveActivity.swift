import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// 백그라운드 디깅 중 잠금화면에 뜨는 Live Activity.
/// 곡 정보는 바로 위 Now Playing과 겹치지 않게 최소한만 두고, 자리의 대부분은 하입 버튼이다.
struct DiggingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiggingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.trackName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(context.state.artistName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HypeButton(state: context.state, size: 30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.trackName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HypeButton(state: context.state, size: 26)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.artistName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                hypeIcon(isHyped: context.state.isHyped, size: 16)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                hypeIcon(isHyped: context.state.isHyped, size: 16)
            }
        }
    }
}

/// 앱의 하입 아이콘과 같은 에셋·같은 브랜드 색을 쓴다.
/// 익스텐션은 앱 번들의 에셋 카탈로그를 못 봐서 `HypeIcon`은 위젯 쪽에 복사돼 있다.
private func hypeIcon(isHyped: Bool, size: CGFloat) -> some View {
    Image("HypeIcon")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .foregroundStyle(isHyped ? Color(red: 0.29, green: 0.25, blue: 0.85) : Color.white.opacity(0.55))
}

/// 탭하면 `LiveActivityIntent`가 **앱 프로세스에서** 돌아 기존 하입 경로를 그대로 탄다.
/// 화면 갱신은 앱이 `Activity.update`로 밀어준다 — 여기서 상태를 들고 있지 않는다.
private struct HypeButton: View {
    let state: DiggingActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Button(intent: ToggleHypeIntent(trackId: state.trackId)) {
            hypeIcon(isHyped: state.isHyped, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isHyped ? "Unhype" : "Hype")
    }
}
