import SwiftUI

/// The Currents mark: a fish leaping up and to the right, its body open and
/// its eye solid. Built from design/brand/currents-fish.svg, normalised to a
/// unit square and scaled to fit the frame. Fill it with even-odd so the body
/// stays open:
///
///     CurrentsMark().fill(tint, style: FillStyle(eoFill: true))
struct CurrentsMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var p = Path()
        p.move(to: pt(0.9564, 0.1345))
        p.addLine(to: pt(0.9252, 0.0691))
        p.addCurve(to: pt(0.9216, 0.0616), control1: pt(0.9240, 0.0665), control2: pt(0.9228, 0.0640))
        p.addLine(to: pt(0.9163, 0.0506))
        p.addCurve(to: pt(0.9091, 0.0427), control1: pt(0.9147, 0.0472), control2: pt(0.9120, 0.0447))
        p.addCurve(to: pt(0.9060, 0.0388), control1: pt(0.9081, 0.0415), control2: pt(0.9071, 0.0399))
        p.addCurve(to: pt(0.7654, 0.0000), control1: pt(0.8825, 0.0153), control2: pt(0.8273, 0.0000))
        p.addCurve(to: pt(0.4862, 0.1149), control1: pt(0.7041, 0.0000), control2: pt(0.5862, 0.0149))
        p.addCurve(to: pt(0.3350, 0.3815), control1: pt(0.3980, 0.2031), control2: pt(0.3631, 0.3020))
        p.addCurve(to: pt(0.2754, 0.5038), control1: pt(0.3167, 0.4334), control2: pt(0.3008, 0.4783))
        p.addCurve(to: pt(0.2091, 0.5273), control1: pt(0.2558, 0.5233), control2: pt(0.2347, 0.5273))
        p.addCurve(to: pt(0.1827, 0.5264), control1: pt(0.2004, 0.5273), control2: pt(0.1916, 0.5269))
        p.addCurve(to: pt(0.1525, 0.5254), control1: pt(0.1728, 0.5260), control2: pt(0.1627, 0.5254))
        p.addCurve(to: pt(0.0238, 0.5773), control1: pt(0.1167, 0.5254), control2: pt(0.0698, 0.5313))
        p.addCurve(to: pt(0.0179, 0.5955), control1: pt(0.0190, 0.5821), control2: pt(0.0168, 0.5889))
        p.addCurve(to: pt(0.0220, 0.6051), control1: pt(0.0184, 0.5991), control2: pt(0.0199, 0.6024))
        p.addLine(to: pt(0.0482, 0.6693))
        p.addCurve(to: pt(0.0592, 0.6804), control1: pt(0.0504, 0.6745), control2: pt(0.0544, 0.6783))
        p.addCurve(to: pt(0.0639, 0.6839), control1: pt(0.0606, 0.6818), control2: pt(0.0622, 0.6830))
        p.addLine(to: pt(0.2649, 0.7875))
        p.addLine(to: pt(0.3686, 0.9886))
        p.addCurve(to: pt(0.3841, 0.9998), control1: pt(0.3716, 0.9946), control2: pt(0.3774, 0.9987))
        p.addCurve(to: pt(0.3874, 1.0000), control1: pt(0.3852, 0.9999), control2: pt(0.3863, 1.0000))
        p.addCurve(to: pt(0.4024, 0.9938), control1: pt(0.3929, 1.0000), control2: pt(0.3984, 0.9978))
        p.addCurve(to: pt(0.4533, 0.8349), control1: pt(0.4585, 0.9377), control2: pt(0.4556, 0.8807))
        p.addCurve(to: pt(0.4759, 0.7422), control1: pt(0.4514, 0.7977), control2: pt(0.4499, 0.7683))
        p.addCurve(to: pt(0.5982, 0.6826), control1: pt(0.5014, 0.7168), control2: pt(0.5463, 0.7010))
        p.addCurve(to: pt(0.8648, 0.5314), control1: pt(0.6777, 0.6545), control2: pt(0.7766, 0.6195))
        p.addCurve(to: pt(0.9783, 0.2846), control1: pt(0.9303, 0.4659), control2: pt(0.9706, 0.3783))
        p.addCurve(to: pt(0.9564, 0.1345), control1: pt(0.9832, 0.2261), control2: pt(0.9743, 0.1696))
        p.closeSubpath()
        p.move(to: pt(0.1805, 0.5688))
        p.addCurve(to: pt(0.2090, 0.5697), control1: pt(0.1902, 0.5692), control2: pt(0.1997, 0.5697))
        p.addCurve(to: pt(0.3053, 0.5337), control1: pt(0.2388, 0.5697), control2: pt(0.2736, 0.5655))
        p.addCurve(to: pt(0.3750, 0.3956), control1: pt(0.3376, 0.5015), control2: pt(0.3549, 0.4524))
        p.addCurve(to: pt(0.5162, 0.1449), control1: pt(0.4030, 0.3162), control2: pt(0.4348, 0.2263))
        p.addCurve(to: pt(0.7654, 0.0424), control1: pt(0.6053, 0.0557), control2: pt(0.7106, 0.0424))
        p.addCurve(to: pt(0.8761, 0.0688), control1: pt(0.8268, 0.0424), control2: pt(0.8659, 0.0586))
        p.addCurve(to: pt(0.8000, 0.4287), control1: pt(0.9064, 0.0992), control2: pt(0.9386, 0.2901))
        p.addCurve(to: pt(0.5492, 0.5699), control1: pt(0.7186, 0.5101), control2: pt(0.6286, 0.5419))
        p.addCurve(to: pt(0.4111, 0.6395), control1: pt(0.4924, 0.5899), control2: pt(0.4434, 0.6073))
        p.addCurve(to: pt(0.3761, 0.7643), control1: pt(0.3718, 0.6789), control2: pt(0.3740, 0.7243))
        p.addCurve(to: pt(0.3567, 0.8679), control1: pt(0.3779, 0.7997), control2: pt(0.3796, 0.8334))
        p.addLine(to: pt(0.2646, 0.6894))
        p.addCurve(to: pt(0.2555, 0.6802), control1: pt(0.2626, 0.6854), control2: pt(0.2594, 0.6822))
        p.addLine(to: pt(0.0769, 0.5881))
        p.addCurve(to: pt(0.1806, 0.5688), control1: pt(0.1137, 0.5637), control2: pt(0.1481, 0.5672))
        p.closeSubpath()
        p.move(to: pt(0.7619, 0.1962))
        p.addCurve(to: pt(0.7023, 0.2558), control1: pt(0.7619, 0.2291), control2: pt(0.7352, 0.2558))
        p.addCurve(to: pt(0.6427, 0.1962), control1: pt(0.6694, 0.2558), control2: pt(0.6427, 0.2291))
        p.addCurve(to: pt(0.7023, 0.1366), control1: pt(0.6427, 0.1633), control2: pt(0.6694, 0.1366))
        p.addCurve(to: pt(0.7619, 0.1962), control1: pt(0.7352, 0.1366), control2: pt(0.7619, 0.1633))
        p.closeSubpath()
        return p
    }
}

extension CurrentsMark {
    /// The mark filled in one colour, open body included.
    func filled(_ color: Color) -> some View {
        fill(color, style: FillStyle(eoFill: true))
    }
}
