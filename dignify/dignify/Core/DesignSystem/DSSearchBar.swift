import SwiftUI

struct DSSearchBar: View {
    @Binding var text: String
    let placeholder: String
    var foregroundStyle: Color = DSColor.textPrimary
    var backgroundStyle: Color = DSColor.surface
    var borderStyle: Color = DSColor.borderLight
    var showsClearButton: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textTertiary)

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(foregroundStyle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

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
    }
}

#Preview {
    @Previewable @State var text = ""

    DSSearchBar(text: $text, placeholder: "아티스트, 트랙, 장르 검색")
        .padding()
}
