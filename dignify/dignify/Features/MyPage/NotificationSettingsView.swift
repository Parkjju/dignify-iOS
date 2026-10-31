import SwiftUI
import PostHog
import UserNotifications

/// 마이 › 알림. 광고성 알림 수신 동의(서버 값)와 OS 알림 권한을 **따로** 보여 준다 —
/// OS 권한은 광고 수신 동의가 아니다(KISA 안내서 Q&A 02-03). 둘 중 하나만 켜져 있으면
/// 큐레이션·신곡·주간 추천 알림은 안 온다.
struct NotificationSettingsView: View {
    @Environment(AppSession.self) private var session
    @AppStorage(AppSession.adPushConsentKey) private var adPush = false
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { adPush }, set: { change($0) })) {
                    Text("Ad notifications")
                        .font(.system(size: 15))
                        .foregroundStyle(DSColor.textPrimary)
                }
                .tint(DSColor.brand)
                .disabled(saving)
                Text("New tracks from artists you like, weekly picks, and our curated sets. These are advertising information.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textTertiary)
                if failed {
                    Text("Couldn't save. Please try again.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.destructive)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 20).padding(.vertical, 8)

            // 권한을 정하기 전엔 설정 앱에 알림 항목이 없다 — 그땐 시스템 팝업을 띄운다.
            // 정한 뒤엔 시스템 팝업이 다시 안 뜨니 설정 앱의 이 앱 알림 화면으로 보낸다.
            Button {
                if status == .notDetermined {
                    session.requestPushAuthorization(source: "settings")
                } else {
                    UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
                }
            } label: {
                HStack {
                    Text("System notifications")
                        .font(.system(size: 15))
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    Text(status == .denied ? "Off" : status == .notDetermined ? "Not set" : "On")
                        .font(.system(size: 15))
                        .foregroundStyle(DSColor.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .padding(.horizontal, 20)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 8)
        .background(DSColor.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { status = await session.pushAuthorizationStatus() }
        // 설정 앱에서 켜고 돌아오면 바로 반영한다.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { status = await session.pushAuthorizationStatus() }
        }
    }

    /// 서버가 받은 뒤에만 토글이 바뀐다 — 동의는 처리 결과를 통지해야 하는 기록이라 낙관적으로 먼저 바꾸지 않는다.
    /// 켤 때 OS 권한이 아직이면 시스템 팝업을, 거부면 설정 앱을 같이 띄운다(`acceptAdPush`).
    private func change(_ on: Bool) {
        failed = false
        saving = true
        PostHogSDK.shared.capture(on ? "ad_consent_accepted" : "ad_consent_declined", properties: ["source": "settings"])
        Task {
            // `adPush`(@AppStorage)는 UserDefaults에 쓴 직후엔 아직 옛 값일 수 있다 — 결과는 반환값으로 본다.
            let saved = on ? await session.acceptAdPush(source: "settings") : await session.setAdPushConsent(false)
            failed = !saved
            saving = false
            status = await session.pushAuthorizationStatus()
        }
    }
}
