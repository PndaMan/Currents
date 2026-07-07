import SwiftUI
import MapKit

/// A small world map showing where a species is observed, using iNaturalist's
/// observation-density grid tiles for the taxon. A lightweight distribution
/// map — not a formal range polygon, but a real global picture of where the
/// species turns up. Renders via MKMapView because SwiftUI's Map can't draw
/// tile overlays.
struct SpeciesRangeMapView: UIViewRepresentable {
    let taxonId: Int

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        // Whole-world starting view.
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: 0),
            span: MKCoordinateSpan(latitudeDeltaWrapped: 140, longitudeDelta: 320)
        ), animated: false)
        addOverlay(to: map, context: context)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if context.coordinator.taxonId != taxonId {
            map.removeOverlays(map.overlays)
            addOverlay(to: map, context: context)
        }
    }

    private func addOverlay(to map: MKMapView, context: Context) {
        context.coordinator.taxonId = taxonId
        let template = "https://api.inaturalist.org/v1/grid/{z}/{x}/{y}.png?taxon_id=\(taxonId)"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = false
        map.addOverlay(overlay, level: .aboveLabels)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var taxonId: Int?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private extension MKCoordinateSpan {
    /// Clamp latitude delta to a valid range.
    init(latitudeDeltaWrapped lat: Double, longitudeDelta lon: Double) {
        self.init(latitudeDelta: min(lat, 170), longitudeDelta: min(lon, 359))
    }
}
