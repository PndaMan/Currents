import SwiftUI
import MapKit

/// UIKit-backed map that renders the cacheable satellite tile overlay as the
/// base map. SwiftUI's `Map` cannot draw an `MKTileOverlay`, which is why the
/// tiles the app caches were never visible anywhere — this view is what makes
/// the cached map the *main* map: every tile fetched while online is served
/// from disk when there's no signal.
struct OfflineMapView: UIViewRepresentable {
    let overlay: OfflineTileOverlay
    var spots: [Spot]
    var catches: [CatchDetail]
    var waterbodies: [Waterbody]
    var spotScores: [String: Int]
    var waterbodyScores: [Int64: Int]
    var accent: Color
    /// Optional overlay tile layers (off by default). The radar overlay is
    /// built asynchronously by the parent (it needs a fetched frame path).
    var showNautical: Bool = false
    var radarOverlay: MKTileOverlay? = nil

    /// Set to move the camera (search result, recentre button); consumed once.
    @Binding var flyTo: CLLocationCoordinate2D?
    var onSelectSpot: (Spot) -> Void
    var onSelectWaterbody: (Waterbody) -> Void
    var onTap: (CLLocationCoordinate2D) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.addOverlay(overlay, level: .aboveLabels)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        context.coordinator.centerInitially(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if let target = flyTo {
            map.setRegion(
                MKCoordinateRegion(center: target, latitudinalMeters: 2000, longitudinalMeters: 2000),
                animated: true
            )
            DispatchQueue.main.async { flyTo = nil }
        }
        context.coordinator.syncAnnotations(on: map)
        context.coordinator.syncOverlays(on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Annotations

    final class SpotAnnotation: NSObject, MKAnnotation {
        let spot: Spot
        let score: Int?
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        }
        var title: String? { spot.name }
        var subtitle: String? {
            score.map { "Bite \($0)" }
        }
        init(spot: Spot, score: Int?) {
            self.spot = spot
            self.score = score
        }
    }

    final class CatchAnnotation: NSObject, MKAnnotation {
        let detail: CatchDetail
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            )
        }
        var title: String? { detail.species?.commonName ?? "Catch" }
        init(detail: CatchDetail) {
            self.detail = detail
        }
    }

    final class WaterbodyAnnotation: NSObject, MKAnnotation {
        let waterbody: Waterbody
        let score: Int?
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: waterbody.latitude, longitude: waterbody.longitude)
        }
        var title: String? { waterbody.name }
        var subtitle: String? {
            let type = waterbody.type.rawValue.capitalized
            return score.map { "\(type) · Bite \($0)" } ?? type
        }
        init(waterbody: Waterbody, score: Int?) {
            self.waterbody = waterbody
            self.score = score
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: OfflineMapView
        private var fingerprint = ""
        private var seamarkOverlay: MKTileOverlay?
        private var currentRadarOverlay: MKTileOverlay?

        init(parent: OfflineMapView) {
            self.parent = parent
        }

        /// Add/remove the optional nautical + radar tile overlays to match the
        /// current toggles, keeping them above the satellite base.
        func syncOverlays(on map: MKMapView) {
            // Nautical (OpenSeaMap seamarks)
            if parent.showNautical, seamarkOverlay == nil {
                let o = SeamarkTileOverlay()
                seamarkOverlay = o
                map.addOverlay(o, level: .aboveLabels)
            } else if !parent.showNautical, let o = seamarkOverlay {
                map.removeOverlay(o)
                seamarkOverlay = nil
            }

            // Radar (RainViewer) — identity changes when a new frame is fetched.
            if currentRadarOverlay !== parent.radarOverlay {
                if let old = currentRadarOverlay { map.removeOverlay(old) }
                currentRadarOverlay = parent.radarOverlay
                if let new = parent.radarOverlay { map.addOverlay(new, level: .aboveLabels) }
            }
        }

        func centerInitially(_ map: MKMapView) {
            // Anchor to the last cached-area center (survives launches with no
            // GPS fix yet); fall back to a wide default.
            let d = UserDefaults.standard
            if let lat = d.object(forKey: "offlineCacheAnchorLat") as? Double,
               let lon = d.object(forKey: "offlineCacheAnchorLon") as? Double {
                map.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    latitudinalMeters: 20_000, longitudinalMeters: 20_000
                )
            }
        }

        /// Rebuild pins only when the underlying data actually changed.
        func syncAnnotations(on map: MKMapView) {
            let fp = parent.spots.map(\.id).joined()
                + parent.catches.map(\.catchRecord.id).joined()
                + parent.waterbodies.map { "\($0.id ?? 0)" }.joined()
            guard fp != fingerprint else { return }
            fingerprint = fp

            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(parent.spots.map {
                SpotAnnotation(spot: $0, score: parent.spotScores[$0.id])
            })
            map.addAnnotations(parent.catches.map(CatchAnnotation.init))
            map.addAnnotations(parent.waterbodies.map {
                WaterbodyAnnotation(waterbody: $0, score: parent.waterbodyScores[$0.id ?? 0])
            })
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            view.displayPriority = .defaultHigh

            switch annotation {
            case is SpotAnnotation:
                view.markerTintColor = UIColor(parent.accent)
                view.glyphImage = UIImage(systemName: "mappin.and.ellipse")
            case is CatchAnnotation:
                view.markerTintColor = UIColor(parent.accent).withAlphaComponent(0.85)
                view.glyphImage = UIImage(systemName: "fish.fill")
                view.displayPriority = .defaultLow
            case is WaterbodyAnnotation:
                view.markerTintColor = UIColor.systemTeal
                view.glyphImage = UIImage(systemName: "water.waves")
            default:
                break
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            switch view.annotation {
            case let spot as SpotAnnotation:
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectSpot(spot.spot)
            case let wb as WaterbodyAnnotation:
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectWaterbody(wb.waterbody)
            default:
                break // catches keep their callout
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            // Ignore taps that land on a pin — those are handled by didSelect.
            var hit = map.hitTest(point, with: nil)
            while let v = hit {
                if v is MKAnnotationView { return }
                hit = v.superview
            }
            parent.onTap(map.convert(point, toCoordinateFrom: map))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
