//
//  GenreSelectionView.swift
//  dignify
//
//  Created by 박경준 on 6/30/26.
//

import SwiftUI

struct GenreSelectionView: View {
    @Environment(AppSession.self) private var appSession
    @State private var selectedGenres: Set<Genre> = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    
    private let genres: [Genre] = [
        Genre(id: 43, name: "Indie Pop"),
        Genre(id: 169, name: "Ambient"),
        Genre(id: 45, name: "Korean Indie"),
        Genre(id: 34, name: "Alternative"),
        Genre(id: 316, name: "R&B/Soul"),
        Genre(id: 168, name: "Electronic"),
        Genre(id: 197, name: "Hip-Hop"),
        Genre(id: 181, name: "Folk"),
        Genre(id: 331, name: "Rock"),
        Genre(id: 241, name: "Jazz")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
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
                    ForEach(genres) { genre in
                        let isSelected = selectedGenres.contains(genre)
                        let isDisabled = !isSelected && selectedGenres.count >= 3
                        DSGenreChip(title: genre.name, isSelected: isSelected, isDisabled: isDisabled) {
                            toggle(genre)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 12) {
                if !selectedGenres.isEmpty {
                    Text("\(selectedGenres.map(\.name).sorted().joined(separator: ", ")) 선택됨")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textTertiary)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.destructive)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("완료")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .background {
                Rectangle()
                    .fill(DSColor.background)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DSColor.divider)
                            .frame(height: 1)
                    }
            }
        }
        .background(DSColor.background)
    }
    
    /// 선택 장르를 서버에 저장하고 온보딩 완료 처리 후 signedIn으로 전환한다.
    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await appSession.api.send(.updateGenres(ids: selectedGenres.map(\.id)))
                try await appSession.api.send(.completeOnboarding)
                appSession.authState = .signedIn
            } catch {
                errorMessage = "저장에 실패했어요. 다시 시도해 주세요."
            }
        }
    }

    private func toggle(_ genre: Genre) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else if selectedGenres.count < 3 {
            selectedGenres.insert(genre)
        }
    }
    
    private struct FlowLayout: Layout {
        var spacing: CGFloat = 8
        var rowSpacing: CGFloat = 8

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            let rows = rows(for: subviews, maxWidth: maxWidth)
            let height = rows.reduce(CGFloat.zero) { $0 + $1.height }
                + CGFloat(max(rows.count - 1, 0)) * rowSpacing

            return CGSize(width: maxWidth, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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

        private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
            var rows: [Row] = []
            var currentElements: [Element] = []
            var currentWidth: CGFloat = 0
            var currentHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                let nextWidth = currentElements.isEmpty ? size.width : currentWidth + spacing + size.width

                if nextWidth > maxWidth, !currentElements.isEmpty {
                    rows.append(Row(elements: currentElements, height: currentHeight))
                    currentElements = [Element(subview: subview, size: size)]
                    currentWidth = size.width
                    currentHeight = size.height
                } else {
                    currentElements.append(Element(subview: subview, size: size))
                    currentWidth = nextWidth
                    currentHeight = max(currentHeight, size.height)
                }
            }

            if !currentElements.isEmpty {
                rows.append(Row(elements: currentElements, height: currentHeight))
            }

            return rows
        }

        private struct Row {
            let elements: [Element]
            let height: CGFloat
        }

        private struct Element {
            let subview: LayoutSubview
            let size: CGSize
        }
    }
}

#Preview {
    GenreSelectionView()
        .environment(AppSession())
}
