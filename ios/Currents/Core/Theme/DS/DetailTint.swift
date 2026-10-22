import SwiftUI

extension View {
    /// Luma's art-colour fade at the top of a pushed detail page: the tint at
    /// 34 percent fading into the page background over 560 pt. Apply to the
    /// page's ScrollView or List. Pass nil for a plain background.
    ///
    /// It also gives the navigation bar the hard scroll edge effect, so text
    /// that scrolls under the inline title is cut off behind an opaque edge
    /// instead of showing through the default soft blur.
    func detailTint(_ color: Color?) -> some View {
        background {
            ZStack(alignment: .top) {
                Color.dsBackground
                if let color {
                    LinearGradient(colors: [color.opacity(0.34), color.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 560)
                        .animation(.easeInOut(duration: DS.Motion.slow), value: color)
                }
            }
            .ignoresSafeArea()
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// The same hard top edge without the tint, for pushed pages and sheets
    /// on the plain background.
    func detailScrollEdge() -> some View {
        scrollEdgeEffectStyle(.hard, for: .top)
    }
}
