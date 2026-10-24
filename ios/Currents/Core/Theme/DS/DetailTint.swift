import SwiftUI

extension View {
    /// Luma's art-colour fade at the top of a pushed detail page: the tint at
    /// 17 percent in dark (10 percent in light) fading into the page
    /// background over `height` points. Apply to the page's ScrollView or
    /// List. Pass nil for a plain background. Pass a smaller height when the
    /// first card sits high on the page, so the wash ends above it.
    ///
    /// It also gives the navigation bar the hard scroll edge effect, so text
    /// that scrolls under the inline title is cut off behind an opaque edge
    /// instead of showing through the default soft blur.
    func detailTint(_ color: Color?, height: CGFloat = 560) -> some View {
        modifier(DetailTint(color: color, height: height))
    }

    /// The same hard top edge without the tint, for pushed pages and sheets
    /// on the plain background.
    func detailScrollEdge() -> some View {
        reviewScrollAnchor()
            .scrollEdgeEffectStyle(.hard, for: .top)
    }
}

/// The fade behind `detailTint`. A modifier so it can read the colour
/// scheme: in light mode a 17 percent wash matched the `dsFill` of the first
/// card and swallowed it, so light uses 10 percent.
private struct DetailTint: ViewModifier {
    let color: Color?
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .reviewScrollAnchor()
            .background {
                ZStack(alignment: .top) {
                    Color.dsBackground
                    if let color {
                        LinearGradient(colors: [color.opacity(scheme == .dark ? 0.17 : 0.10), color.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: height)
                            .animation(.easeInOut(duration: DS.Motion.slow), value: color)
                    }
                }
                .ignoresSafeArea()
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
    }
}
