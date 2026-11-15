import SwiftUI

struct JustifiedIconGeometry {
    let itemWidth: CGFloat
    let iconWidth: CGFloat
    let spacing: CGFloat

    func frames(width: CGFloat, heights: [CGFloat]) -> [CGRect] {
        guard !heights.isEmpty else { return [] }
        let width = max(iconWidth, width)
        let naturalStep = itemWidth + spacing
        let columns = max(1, Int((width - iconWidth) / naturalStep) + 1)
        // Short lists flow from the leading edge at their natural spacing.
        // Full rows may stretch slightly; subsequent rows reuse those columns.
        let fullRowStep = columns > 1
            ? min(naturalStep * 1.25, (width - iconWidth) / CGFloat(columns - 1))
            : 0
        let step = heights.count >= columns ? fullRowStep : naturalStep
        var frames: [CGRect] = []
        var top: CGFloat = 0
        for start in stride(from: 0, to: heights.count, by: columns) {
            let end = min(start + columns, heights.count)
            for index in start..<end {
                // Align the visible icons, allowing their centered labels to be wider.
                let center = iconWidth / 2 + CGFloat(index - start) * step
                frames.append(CGRect(x: center - itemWidth / 2, y: top,
                                     width: itemWidth, height: heights[index]))
            }
            top += (heights[start..<end].max() ?? 0) + spacing
        }
        return frames
    }
}

struct JustifiedIconLayout: Layout {
    let itemWidth: CGFloat
    let iconWidth: CGFloat
    let spacing: CGFloat

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        JustifiedIconGeometry(itemWidth: itemWidth, iconWidth: iconWidth, spacing: spacing)
            .frames(width: width, heights: subviews.map {
                $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
            })
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? itemWidth
        let width = proposedWidth.isFinite ? max(iconWidth, proposedWidth) : itemWidth
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
