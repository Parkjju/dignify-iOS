import SwiftUI

/// 피드에 없는 아티스트를 유저가 요청하는 시트. 검색 빈결과·요청 히스토리 두 곳에서 띄운다.
/// 서버는 저장만 하고(수동 리뷰) 성공하면 확인 화면으로 바꾼 뒤 스스로 닫힌다.
/// 로그인 유저만 진입한다(게스트는 호출부에서 게이트).
struct ArtistRequestSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// 검색 빈결과에서 열면 실패한 검색어를 채워준다. 히스토리에서 열면 빈 문자열.
    let prefill: String

    @State private var text: String
    @State private var submitting = false
    @State private var submitted = false
    @FocusState private var focused: Bool

    /// 백엔드 @Size(max=100)와 맞춘 입력 상한.
    private let maxLength = 100

    init(prefill: String = "") {
        self.prefill = prefill
        _text = State(initialValue: String(prefill.prefix(100)))
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if submitted { confirmation } else { form }
        }
        .padding(24)
        .presentationDetents([.height(submitted ? 220 : 280)])
        .presentationBackground(DSColor.background)
        // 성공 화면을 잠깐 보여준 뒤 자동으로 닫는다.
        .onChange(of: submitted) { _, done in
            guard done else { return }
            Task { try? await Task.sleep(for: .seconds(1.4)); dismiss() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Request an artist")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text("Can't find an artist? Tell us who, and we'll look into adding their tracks.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Artist name", text: $text)
                .font(DSTypography.body)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .onChange(of: text) { _, new in
                    if new.count > maxLength { text = String(new.prefix(maxLength)) }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: 12))

            Button(action: submit) {
                Text("Send request")
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DSColor.brand.opacity(canSubmit ? 1 : 0.4),
                               in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit)
        }
        .onAppear { focused = true }
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DSColor.brand)
            Text("Request sent")
                .font(DSTypography.title2)
                .foregroundStyle(DSColor.textPrimary)
            Text("We'll notify you when they're added.")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var canSubmit: Bool { !trimmed.isEmpty && !submitting }

    private func submit() {
        guard canSubmit else { return }
        submitting = true
        Task {
            do {
                try await session.api.send(.requestArtist(artistName: trimmed))
                submitted = true
                // "추가되면 알려드릴게요" 맥락에서 알림 권한을 요청한다.
                session.requestPushAuthorization()
            } catch {
                submitting = false   // 실패 시 그대로 두고 재시도 가능하게.
            }
        }
    }
}
