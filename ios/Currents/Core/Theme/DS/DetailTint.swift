import SwiftUI

extension View {
    /// Luma's art-colour fade at the top of a pushed detail page: the tint at
    /// 34 percent fading into the page background over 560 pt. Apply to the
    /// page's ScrollView. Pass nil for a plain background.
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
    }
}
