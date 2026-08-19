import SwiftUI

/// 릴리즈 노트는 앱 내 로컬 상수. 백엔드 불필요 — 어차피 릴리즈마다 빌드에 실림.
/// 새 버전 추가 시 releases 맨 앞에 한 항목 추가.
struct Release: Identifiable {
    var id: String { version }
    let version: String
    let notes: [LocalizedStringKey]
}

enum Changelog {
    static let releases: [Release] = [
        Release(version: "1.0.10", notes: [
            "Your hypes and reactions no longer go missing after the app has been sitting a while.",
            "The weekly set badge no longer shows up on search results.",
        ]),
        Release(version: "1.0.9", notes: [
            "Your crate now shows every track you've hyped, not just the first few.",
        ]),
        Release(version: "1.0.8", notes: [
            "Picks: put a few tracks together and send them out.",
            "React to other people's picks with an emoji.",
            "Share a pick as a card for Instagram or anywhere else.",
            "Rename a pick after you post it.",
            "Find dignify on Instagram from My Page.",
        ]),
        Release(version: "1.0.7", notes: [
            "Long titles and headlines no longer get cut off on share cards.",
        ]),
        Release(version: "1.0.6", notes: [
            "A special playlist we dug up ourselves now leads your feed every week.",
            "Turn on notifications and we'll tell you when the next one drops.",
            "Open any track in YouTube Music, not just Apple Music.",
            "New here? Take the taste test and we'll pick your genres.",
            "Every genre now comes with a plain-language description.",
            "Retake the test anytime from genre settings.",
        ]),
        Release(version: "1.0.5", notes: [
            "Digging Profile: your taste, typed.",
            "See the gap between what you play and what you keep.",
            "Your hyped tracks now live in your profile.",
            "Share your taste as a card.",
        ]),
        Release(version: "1.0.4", notes: [
            "A quick tutorial to help you get started.",
            "See what's new after every update.",
        ]),
        Release(version: "1.0.3", notes: [
            "Request artists you can't find yet.",
            "Get notified when your request is added.",
        ]),
    ]

    static func has(_ version: String) -> Bool {
        releases.contains { $0.version == version }
    }

    /// 업데이트로 들어온 유저에게만 What's New를 띄운다.
    /// - lastSeen 있음: 다른 버전이면 표시(일반 업데이트).
    /// - lastSeen 빈 값: 이 키가 처음 생긴 빌드의 첫 실행 → 기존 로그인 유저면 표시,
    ///   신규 설치/온보딩 유저(튜토리얼 대상)는 제외.
    /// 노트 없는 버전은 항상 제외.
    static func shouldShowWhatsNew(lastSeen: String, current: String, isReturningUser: Bool) -> Bool {
        guard has(current) else { return false }
        if lastSeen.isEmpty { return isReturningUser }
        return lastSeen != current
    }
}

/// highlight != nil: 업데이트 직후 해당 버전만 표시. nil: 마이페이지에서 전체 버전 로그.
struct WhatsNewView: View {
    var highlight: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var releases: [Release] {
        if let highlight { return Changelog.releases.filter { $0.version == highlight } }
        return Changelog.releases
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What's New")
                    .font(DSTypography.title1)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Version \(release.version)")
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColor.brand)
                            ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(DSColor.brand)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 7)
                                    Text(note)
                                        .font(DSTypography.body)
                                        .foregroundStyle(DSColor.textSecondary)
                                        .lineSpacing(3)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Button { dismiss() } label: { Text("Got it") }
                .buttonStyle(DSPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(DSColor.background)
    }
}

#Preview {
    WhatsNewView()
}
