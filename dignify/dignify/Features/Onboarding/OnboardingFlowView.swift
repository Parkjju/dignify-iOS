import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var appSession
    @State private var selectedGenres: Set<String> = []
    @State private var showsGenreSelection = false

    private let genres = [
        "Indie Pop", "Lo-fi", "Shoegaze", "Ambient", "Korean Indie",
        "Alternative", "R&B/Soul", "Electronic", "Hip-Hop", "Folk",
        "Rock", "Jazz"
    ]

    var body: some View {
        Group {
            if showsGenreSelection {
                genreSelectionView
            } else {
                signInView
            }
        }
        .background(DSColor.background)
    }

    private var signInView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 13) {
                DSBrandMark(size: 64)

                VStack(spacing: 4) {
                    Text("Dignify")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.96)
                        .foregroundStyle(DSColor.brand)

                    Text("인디 음악을 발굴하고\n당신만의 취향을 쌓아가세요.")
                        .font(DSTypography.body)
                        .lineSpacing(4)
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    showsGenreSelection = true
                }
            } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(DSAppleSignInButtonStyle())

            Text("계속 진행하면 이용약관 및 개인정보처리방침에 동의하는 것으로 간주됩니다.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
        }
        .padding(24)
    }

    private var genreSelectionView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("어떤 음악을 좋아하세요?")
                            .font(DSTypography.title1)
                            .tracking(-0.48)
                            .foregroundStyle(DSColor.textPrimary)

                        Text("최대 3개까지 선택할 수 있어요")
                            .font(.system(size: 14))
                            .foregroundStyle(DSColor.textTertiary)
                    }

                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            let isSelected = selectedGenres.contains(genre)
                            let isDisabled = !isSelected && selectedGenres.count >= 3

                            DSGenreChip(title: genre, isSelected: isSelected, isDisabled: isDisabled) {
                                toggleGenre(genre)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if !selectedGenres.isEmpty {
                    Text("\(selectedGenres.sorted().joined(separator: ", ")) 선택됨")
                        .font(.system(size: 13))
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    appSession.authState = .signedIn
                } label: {
                    Text("완료")
                }
                .buttonStyle(DSPrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background {
                Rectangle()
                    .fill(DSColor.background)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 1)
                    }
            }
        }
    }

    private func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else if selectedGenres.count < 3 {
            selectedGenres.insert(genre)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .zero
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing

        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(element.size)
                )
                x += element.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentElements: [FlowElement] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentElements.isEmpty ? size.width : currentWidth + spacing + size.width

            if nextWidth > maxWidth, !currentElements.isEmpty {
                rows.append(FlowRow(elements: currentElements, height: currentHeight))
                currentElements = [FlowElement(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentElements.append(FlowElement(subview: subview, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentElements.isEmpty {
            rows.append(FlowRow(elements: currentElements, height: currentHeight))
        }

        return rows
    }
}

private struct FlowRow {
    let elements: [FlowElement]
    let height: CGFloat
}

private struct FlowElement {
    let subview: LayoutSubview
    let size: CGSize
}

#Preview {
    OnboardingFlowView()
        .environment(AppSession())
}
