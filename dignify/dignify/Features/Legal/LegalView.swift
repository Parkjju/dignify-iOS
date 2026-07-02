import SwiftUI

struct LegalView: View {
    enum DocumentType: Hashable {
        case terms
        case privacy

        var title: LocalizedStringKey {
            switch self {
            case .terms: return "Terms of Service"
            case .privacy: return "Privacy Policy"
            }
        }
    }

    let type: DocumentType

    var body: some View {
        ScrollView {
            Text(type.title)
                .font(DSTypography.title1)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(DSColor.background)
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LegalView(type: .terms)
    }
}
