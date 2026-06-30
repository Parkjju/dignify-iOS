import SwiftUI

struct DSBrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(DSColor.brandLight)

            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Dignify")
    }
}

#Preview {
    DSBrandMark()
        .padding()
}
