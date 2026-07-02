import SwiftUI

/// 좌→우로 채우다 폭을 넘으면 다음 줄로 내리는 태그(칩) 배치용 Layout.
/// 장르 선택/설정 등 칩 그리드에서 공용으로 쓴다.
struct FlowLayout: Layout {
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
