import SwiftUI

/// Map-only values for Explore. Pins and labels sit on satellite imagery of
/// any colour, so they need the separation the rest of the app does without.
extension Color {
    /// Water bodies on the map and in lists: one blue that reads on imagery.
    static let exploreWater = Color(red: 0.35, green: 0.75, blue: 0.98)

    /// Water names drawn as text: the map blue in dark mode, a deeper blue in
    /// light mode so a name still reads against its white halo.
    static let exploreWaterInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.80, blue: 1.0, alpha: 1)
            : UIColor(red: 0.0, green: 0.40, blue: 0.72, alpha: 1)
    })
}

enum ExploreMetrics {
    /// Corner of a bar in the hourly bite strip.
    static let barRadius: CGFloat = 3
    /// Water's round pin and the bite ring around it.
    static let waterDot: CGFloat = 30
    static let waterRing: CGFloat = 40
    /// Fishing access and ramp markers.
    static let placeDot: CGFloat = 26
}

extension View {
    /// Lifts a pin or marker off the map imagery.
    func mapPinShadow() -> some View {
        shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    /// A halo behind text drawn straight on the map, so it reads on any style.
    func mapLabelHalo() -> some View {
        shadow(color: Color.dsBackground, radius: 1)
            .shadow(color: Color.dsBackground, radius: 2)
    }
}
