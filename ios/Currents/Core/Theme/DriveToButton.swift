import SwiftUI
import CoreLocation
import MapKit
import UIKit

/// A "Drive to" menu that offers Waze (first), Apple Maps, then Google Maps for
/// navigating to a coordinate. Uses universal https links for Waze/Google so
/// each opens its app when installed and falls back to the web otherwise — no
/// URL-scheme allowlist needed in Info.plist.
struct DriveToButton: View {
    let coordinate: CLLocationCoordinate2D
    var name: String = ""
    var style: Style = .prominent

    enum Style { case prominent, compact }

    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button { openWaze() } label: { Label("Waze", systemImage: "car.fill") }
            Button { openAppleMaps() } label: { Label("Apple Maps", systemImage: "map.fill") }
            Button { open(googleMapsURL) } label: { Label("Google Maps", systemImage: "mappin.and.ellipse") }
        } label: {
            switch style {
            case .prominent:
                Label("Drive to", systemImage: "car.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CurrentsTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            case .compact:
                Label("Drive to", systemImage: "car.fill")
                    .font(.caption.bold())
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }

    private var googleMapsURL: URL? {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving")
    }

    /// Open Waze at the destination. The `waze://` app scheme opens the app
    /// directly (a comma in `ll` is fine there); if Waze isn't installed we fall
    /// back to the web link with the comma percent-encoded — an unencoded comma
    /// is what made the web page show "something went wrong".
    private func openWaze() {
        Haptics.tap()
        let lat = coordinate.latitude, lon = coordinate.longitude
        let app = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
        let web = URL(string: "https://waze.com/ul?ll=\(lat)%2C\(lon)&navigate=yes")
        if let app {
            UIApplication.shared.open(app, options: [:]) { opened in
                if !opened, let web { UIApplication.shared.open(web) }
            }
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        Haptics.tap()
        openURL(url)
    }

    private func openAppleMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name.isEmpty ? "Destination" : name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
