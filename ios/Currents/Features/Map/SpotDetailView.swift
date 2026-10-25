import SwiftUI

/// A saved spot, pushed on any stack (Explore lists, the Logbook, plans,
/// sessions). A spot saved from a water shows the water's page joined to it.
struct SpotDetailView: View {
    let spot: Spot
    var style: ExplorePlacePage.Style = .page

    init(spot: Spot, style: ExplorePlacePage.Style = .page) {
        self.spot = spot
        self.style = style
    }

    var body: some View {
        ExplorePlacePage(spot: spot, style: style)
    }
}
