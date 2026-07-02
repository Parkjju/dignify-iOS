import SwiftUI

struct DSSearchBar: View {
    @Binding var text: String
    let placeholder: String
    var foregroundStyle: Color = DSColor.textPrimary
    var backgroundStyle: Color = DSColor.surface
    var borderStyle: Color = DSColor.borderLight
    var showsClearButton: Bool = true
    var iconSize: CGFloat = 15
    /// 외부에서 TextField 포커스를 양방향 제어/관찰하고 싶을 때 주입(옵셔널).
    var isFocused: Binding<Bool>? = nil
    /// 키보드 return(검색) 눌렀을 때. 검색 확정형 실행에 사용.
    var onSubmit: (() -> Void)? = nil

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(foregroundStyle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .onSubmit { onSubmit?() }

            if showsClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: DSRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.medium)
                .stroke(borderStyle, lineWidth: 1)
        }
        // 외부 바인딩 ↔ 내부 FocusState 양방향 동기화.
        .onChange(of: fieldFocused) { _, focused in isFocused?.wrappedValue = focused }
        .onChange(of: isFocused?.wrappedValue) { _, focused in
            if let focused, focused != fieldFocused { fieldFocused = focused }
        }
    }
}

#Preview {
    @Previewable @State var text = ""

    DSSearchBar(text: $text, placeholder: "아티스트, 트랙, 장르 검색")
        .padding()
}
