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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleRow("Ad notifications",
                      detail: "New tracks from artists you like, weekly picks, and this week's sets",
                      isOn: Binding(get: { adPush }, set: { changeAdPush($0) }))
            // 광고성이 꺼져 있으면 야간은 꺼진 채로 보인다(서버도 같이 끈다).
            toggleRow("Night-time ad notifications",
                      detail: "New tracks from artists and this week's sets\n(8:00 AM – 9:00 PM)",
                      isOn: Binding(get: { adPush && session.adPushNight == true }, set: { changeNight($0) }))

            Divider().padding(.horizontal, 20).padding(.vertical, 12)

            // 정한 뒤엔 시스템 팝업이 다시 안 뜨니 설정 앱의 이 앱 알림 화면으로 보낸다.
            // 「설정 전」이면 아무 동작 없다(2026-11-17 확정) — 시스템 팝업은 동의 팝업·시트에서만 띄운다.
            Button {
                guard status != .notDetermined else { return }
                UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
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
                .frame(height: 50)
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

    private func toggleRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(DSColor.textPrimary)
            }
            .tint(DSColor.brand)
            .disabled(saving)
            Text(detail)
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// 서버가 받은 뒤에만 토글이 바뀐다 — 동의는 처리 결과를 통지해야 하는 기록이라 낙관적으로 먼저 바꾸지 않는다.
    /// 결과·실패 토스트는 `AppSession`이 띄운다. 켤 때 OS 권한이 설정 전이면 시스템 팝업도 띄운다(`acceptAdPush`).
    private func changeAdPush(_ on: Bool) {
        saving = true
        PostHogSDK.shared.capture(on ? "ad_consent_accepted" : "ad_consent_declined", properties: ["source": "settings"])
        Task {
            _ = on ? await session.acceptAdPush(source: "settings") : await session.setAdPushConsent(false)
            saving = false
            status = await session.pushAuthorizationStatus()
        }
    }

    private func changeNight(_ on: Bool) {
        // 광고성이 꺼진 채 야간을 누르면 저장하지 않고 안내만.
        guard adPush else {
            showNeedsAdConsent()
            return
        }
        saving = true
        PostHogSDK.shared.capture(on ? "ad_night_consent_accepted" : "ad_night_consent_declined",
                                  properties: ["source": "settings"])
        Task {
            // 다른 기기에서 광고성을 끈 뒤라 서버가 거절하면(409) 같은 안내.
            if await session.setAdPushNightConsent(on) == .needsAdConsent { showNeedsAdConsent() }
            saving = false
        }
    }

    private func showNeedsAdConsent() {
        session.toast = DSToastItem(
            title: String(localized: "Turn on ad notifications first."),
            message: String(localized: "You need to opt in to ad notifications before setting night-time ones."))
    }
}
