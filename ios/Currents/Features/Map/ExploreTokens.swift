import SwiftUI

/// Map-only values for Explore. Pins and labels sit on satellite imagery of
/// any colour, so they need the separation the rest of the app does without.
extension Color {
    /// Water bodies on the map and in lists: one blue that reads on imagery.
    static let exploreWater = Color(red: 0.35, green: 0.75, blue: 0.98)
}

enum ExploreMetrics {
    /// Corner of a bar in the hourly bite strip.
    static let barRadius: CGFloat = 3
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
