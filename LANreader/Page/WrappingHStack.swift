import SwiftUI

struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 2
    var verticalSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = size.width + horizontalSpacing * 2
            let itemHeight = size.height + verticalSpacing * 2

            if currentX + itemWidth > maxWidth, currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX + horizontalSpacing, y: currentY + verticalSpacing))

            currentX += itemWidth
            lineHeight = max(lineHeight, itemHeight)
            totalWidth = max(totalWidth, currentX)
            totalHeight = max(totalHeight, currentY + lineHeight)
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// Convenience wrapper for generic content
extension WrappingHStack {
    struct ForEach<Model: Hashable, Content: View>: View {
        let models: [Model]
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let content: (Model) -> Content

        init(
            _ models: [Model],
            horizontalSpacing: CGFloat = 2,
            verticalSpacing: CGFloat = 2,
            @ViewBuilder content: @escaping (Model) -> Content
        ) {
            self.models = models
            self.horizontalSpacing = horizontalSpacing
            self.verticalSpacing = verticalSpacing
            self.content = content
        }

        var body: some View {
            WrappingHStack(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
                SwiftUI.ForEach(models, id: \.self) { model in
                    content(model)
                }
            }
        }
    }
}
