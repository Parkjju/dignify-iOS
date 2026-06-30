import SwiftUI

struct DSGenreChip: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(backgroundColor, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                }
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isDisabled)
    }

    private var foregroundColor: Color {
        if isSelected { return .white }
        if isDisabled { return Color(hex: 0xD1D5DB) }
        return Color(hex: 0x374151)
    }

    private var backgroundColor: Color {
        isSelected ? DSColor.brand : DSColor.background
    }

    private var borderColor: Color {
        if isSelected { return DSColor.brand }
        if isDisabled { return DSColor.borderLight }
        return DSColor.border
    }
}

#Preview {
    VStack(spacing: 12) {
        DSGenreChip(title: "Indie Pop", isSelected: true) {}
        DSGenreChip(title: "Lo-fi", isSelected: false) {}
        DSGenreChip(title: "Shoegaze", isSelected: false, isDisabled: true) {}
    }
    .padding()
}
