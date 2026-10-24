import SwiftUI
import MapKit

/// Generates a shareable image card for a saved spot. A spot has no photo,
/// so the map is the hero.
@MainActor
enum SpotShareCard {

    /// A universal Apple Maps link that drops a pin at exactly this spot.
    /// Opens in Apple Maps on iOS and the web elsewhere, ideal as the caption
    /// when the image is shared to WhatsApp, Messages, etc.
    static func mapsLink(for spot: Spot) -> String {
        let name = spot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Spot"
        return "https://maps.apple.com/?ll=\(spot.latitude),\(spot.longitude)&q=\(name)"
    }

    /// The caption text attached alongside the image when sharing.
    static func caption(for spot: Spot) -> String {
        "\(spot.name): my fishing spot on Currents\n\(mapsLink(for: spot))"
    }

    /// Render a shareable spot card (1080 by 1350, Instagram 4:5): the spot
    /// on a satellite map with a pin, then its name, place and numbers, in the
    /// same card family as the trip and tournament cards.
    static func render(spot: Spot, catchCount: Int, biteScore: Int?) async -> UIImage? {
        let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        let snapshot = await captureMapSnapshot(coordinate: coordinate, size: SpotShareCardView.mapSize)
        return ShareCardRenderer.image(
            SpotShareCardView(spot: spot, catchCount: catchCount, biteScore: biteScore,
                              map: snapshot?.image))
    }

    // MARK: - Map snapshot

    private static func captureMapSnapshot(
        coordinate: CLLocationCoordinate2D, size: CGSize
    ) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 1400, longitudinalMeters: 1400
        )
        options.size = size
        options.mapType = .hybrid
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        return try? await MKMapSnapshotter(options: options).start()
    }
}

// MARK: - Card

private struct SpotShareCardView: View {
    /// The map panel inside the card's padding. The snapshot is centred on
    /// the spot, so the pin sits in the middle.
    static let mapSize = CGSize(width: 320, height: 250)

    let spot: Spot
    let catchCount: Int
    let biteScore: Int?
    let map: UIImage?

    var body: some View {
        ShareCardCanvas {
            mapPanel
            HStack(spacing: DS.Space.s2) {
                Image(systemName: spot.type.icon)
                Text(spot.type == .general ? "Fishing spot" : spot.type.label)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(Color.dsText2)
            .padding(.top, DS.Space.s4)
            Text(spot.name)
                .font(.title.bold())
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                .font(.footnote.monospaced())
                .foregroundStyle(Color.dsText3)
            HStack(spacing: DS.Space.s2) {
                ShareCardStat(value: "\(catchCount)", label: catchCount == 1 ? "Catch" : "Catches")
                if let biteScore {
                    ShareCardStat(value: "\(biteScore)", label: "Bite score")
                }
            }
            .padding(.top, DS.Space.s3)
            Spacer(minLength: DS.Space.s3)
            ShareCardFooter()
        }
    }

    private var mapPanel: some View {
        Color.clear
            .frame(height: Self.mapSize.height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let map {
                    Image(uiImage: map)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.dsFill
                        DS.accent.opacity(0.22)
                    }
                }
            }
            .overlay {
                Image(systemName: "mappin.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, DS.accent)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
