import SwiftUI
import MapKit

/// A water body (dam, lake, river, estuary, coast). Once saved it is a spot,
/// and the same page shows your catches there too.
struct WaterbodyDetailView: View {
    let waterbody: Waterbody
    var style: ExplorePlacePage.Style = .page

    init(waterbody: Waterbody, style: ExplorePlacePage.Style = .page) {
        self.waterbody = waterbody
        self.style = style
    }

    var body: some View {
        ExplorePlacePage(waterbody: waterbody, style: style)
    }
}

// MARK: - Depth Profile Cross-Section

/// Stylised cross-section of the water column: shoreline on both sides
/// sloping down to the maximum depth, with a dashed average-depth line.
struct DepthProfileView: View {
    let maxDepthM: Double
    var avgDepthM: Double?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Water fill
                bedPath(in: size)
                    .fill(Color.exploreWater.opacity(0.22))

                // Lakebed outline
                bedPath(in: size)
                    .stroke(Color.exploreWater.opacity(0.6), lineWidth: 1.5)

                // Surface line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addLine(to: CGPoint(x: size.width, y: 1))
                }
                .stroke(Color.exploreWater, lineWidth: 2)

                // Average depth dashed line
                if let avg = avgDepthM, maxDepthM > 0, avg < maxDepthM {
                    let y = size.height * CGFloat(min(0.9, avg / maxDepthM))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.dsText3)

                    Text("Average \(Units.depth(m: avg))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .padding(.horizontal, 4)
                        .background(Color.dsBackground, in: Capsule())
                        .offset(x: 6, y: y - 14)
                }

                // Max depth label at the deepest point
                Text(Units.depth(m: maxDepthM))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .position(x: size.width * 0.55, y: size.height - 10)

                // Surface label
                Text("Surface")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.dsText2)
                    .offset(x: 6, y: 5)
            }
        }
    }

    /// Asymmetric basin: gentle slope from the left shore, deepest at ~55%
    /// of the width, steeper climb to the right shore.
    private func bedPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        return Path { p in
            p.move(to: .zero)
            p.addCurve(
                to: CGPoint(x: w * 0.55, y: h * 0.92),
                control1: CGPoint(x: w * 0.12, y: h * 0.25),
                control2: CGPoint(x: w * 0.38, y: h * 0.92)
            )
            p.addCurve(
                to: CGPoint(x: w, y: 0),
                control1: CGPoint(x: w * 0.75, y: h * 0.92),
                control2: CGPoint(x: w * 0.9, y: h * 0.3)
            )
            p.closeSubpath()
        }
    }
}

// MARK: - Flow Layout (for structure type pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(
                x: bounds.minX + position.x,
                y: bounds.minY + position.y
            ), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
