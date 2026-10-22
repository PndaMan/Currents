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
    /// Animated flow fields (off by default). Wind uses live weather; current
    /// uses a wind-driven surface-drift approximation.
    var showWind: Bool = false
    var showCurrent: Bool = false
    var windSpeedKmh: Double? = nil
    var windFromDeg: Double = 0

    /// Set to move the camera (search result, recentre button); consumed once.
    @Binding var flyTo: CLLocationCoordinate2D?
    var onSelectSpot: (Spot) -> Void
    var onSelectWaterbody: (Waterbody) -> Void
    var onTap: (CLLocationCoordinate2D) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void
    /// Public boat ramps and access points, when that layer is on.
    var ramps: [BoatRamp] = []
    var onSelectRamp: ((BoatRamp) -> Void)? = nil
    var onSelectCatch: ((CatchDetail) -> Void)? = nil
    /// A photo stack that zooming cannot split, newest first. Without it,
    /// such a stack opens its newest catch through `onSelectCatch`.
    var onSelectCatches: (([CatchDetail]) -> Void)? = nil
    /// Long press drops a new spot there.
    var onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Distance from the top safe area to the compass, so it clears the
    /// search bar and chips drawn over the map.
    var compassTopInset: CGFloat = 60

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        // Disable the built-in compass (it sits top-right when rotated, clipping
        // under our right-hand button column) and place our own top-LEFT.
        map.showsCompass = false
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.addOverlay(overlay, level: .aboveLabels)

        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive   // only shows while rotated
        compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            compass.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: compassTopInset),
        ])

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        press.minimumPressDuration = 0.5
        press.delegate = context.coordinator
        map.addGestureRecognizer(press)

        // Animated flow fields sit above the map, below the buttons, and never
        // intercept touches.
        let current = WindFieldView(frame: map.bounds)
        current.mode = .current
        current.tint = UIColor.systemTeal
        current.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.addSubview(current)
        context.coordinator.currentField = current

        let wind = WindFieldView(frame: map.bounds)
        wind.mode = .wind
        wind.tint = .white
        wind.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.addSubview(wind)
        context.coordinator.windField = wind

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
        context.coordinator.syncFlowFields(on: map)
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
            let type = ExploreFormat.waterType(waterbody.type)
            return score.map { "\(type), bite \($0)" } ?? type
        }
        init(waterbody: Waterbody, score: Int?) {
            self.waterbody = waterbody
            self.score = score
        }
    }

    final class RampAnnotation: NSObject, MKAnnotation {
        let ramp: BoatRamp
        var coordinate: CLLocationCoordinate2D { ramp.coordinate }
        var title: String? { ramp.name }
        init(ramp: BoatRamp) {
            self.ramp = ramp
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: OfflineMapView
        private var fingerprint = ""
        private var seamarkOverlay: MKTileOverlay?
        private var currentRadarOverlay: MKTileOverlay?
        weak var windField: WindFieldView?
        weak var currentField: WindFieldView?

        init(parent: OfflineMapView) {
            self.parent = parent
        }

        /// Enable/disable the animated wind & current fields and push the latest
        /// wind vector + map heading into them.
        func syncFlowFields(on map: MKMapView) {
            let heading = map.camera.heading
            for (field, on) in [(windField, parent.showWind), (currentField, parent.showCurrent)] {
                guard let field else { continue }
                field.isHidden = !on
                field.mapHeading = heading
                field.windFromDeg = parent.windFromDeg
                // Setting the speed starts/stops the CADisplayLink internally.
                field.windSpeedKmh = on ? parent.windSpeedKmh : nil
            }
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

        /// Rebuild pins only when the underlying data actually changed. A
        /// catch's photos and species count too, so an edited catch redraws.
        func syncAnnotations(on map: MKMapView) {
            let catchKey: String = parent.catches.map { (d: CatchDetail) -> String in
                let r = d.catchRecord
                return "\(r.id)\(r.photoPaths ?? r.photoPath ?? "")\(r.speciesId ?? 0)"
            }.joined()
            let fp = parent.spots.map(\.id).joined()
                + catchKey
                + parent.waterbodies.map { "\($0.id ?? 0)" }.joined()
                + parent.ramps.map(\.id).joined()
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
            map.addAnnotations(parent.ramps.map(RampAnnotation.init))
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            // Catches draw as their photos, and merge into photo stacks.
            if let cluster = annotation as? MKClusterAnnotation,
               cluster.memberAnnotations.allSatisfy({ $0 is CatchAnnotation }) {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: CatchStackAnnotationView.reuseID)
                    as? CatchStackAnnotationView)
                    ?? CatchStackAnnotationView(annotation: cluster, reuseIdentifier: CatchStackAnnotationView.reuseID)
                view.annotation = cluster
                view.canShowCallout = false
                return view
            }
            if annotation is CatchAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: CatchPhotoAnnotationView.reuseID)
                    as? CatchPhotoAnnotationView)
                    ?? CatchPhotoAnnotationView(annotation: annotation, reuseIdentifier: CatchPhotoAnnotationView.reuseID)
                view.annotation = annotation
                // Without a catch handler, the name and date show in a callout.
                view.canShowCallout = parent.onSelectCatch == nil
                return view
            }
            if let cluster = annotation as? MKClusterAnnotation {
                let id = "cluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: id)
                view.annotation = cluster
                view.canShowCallout = false
                // Water clusters stay blue, like single water pins.
                let allWater = cluster.memberAnnotations.allSatisfy { $0 is WaterbodyAnnotation }
                view.markerTintColor = allWater ? UIColor(Color.exploreWater) : UIColor(parent.accent)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.accessibilityLabel = "\(cluster.memberAnnotations.count) \(allWater ? "waters" : "places"). Zooms in."
                return view
            }
            let id = "pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            view.displayPriority = .defaultHigh
            // Nearby pins merge into a numbered marker that zooms in on tap.
            // Water, ramps and catches each cluster on their own, so a
            // cluster never mixes water and spots.
            view.clusteringIdentifier = annotation is RampAnnotation ? "ramps"
                : annotation is WaterbodyAnnotation ? "water" : "places"
            view.glyphText = nil
            view.glyphTintColor = .white

            switch annotation {
            case is SpotAnnotation:
                view.markerTintColor = UIColor(parent.accent)
                view.glyphImage = UIImage(systemName: "mappin.and.ellipse")
            case let w as WaterbodyAnnotation:
                view.markerTintColor = UIColor(Color.exploreWater)
                view.glyphImage = UIImage(systemName: ExploreFormat.waterIcon(w.waterbody.type))
            case let r as RampAnnotation:
                view.markerTintColor = UIColor.white
                view.glyphTintColor = UIColor(ExploreFormat.placeTint(r.ramp.kind))
                view.glyphImage = UIImage(systemName: r.ramp.kind.icon)
                view.displayPriority = .defaultLow
                view.canShowCallout = false
            default:
                break
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            switch view.annotation {
            case let cluster as MKClusterAnnotation:
                mapView.deselectAnnotation(cluster, animated: false)
                // A stack that zooming can no longer split (catches logged on
                // the same few metres) lists its catches instead.
                if let stack = Self.inseparableCatches(cluster.memberAnnotations, on: mapView) {
                    if let onSelectCatches = parent.onSelectCatches {
                        onSelectCatches(stack)
                        return
                    }
                    if let onSelectCatch = parent.onSelectCatch, let newest = stack.first {
                        onSelectCatch(newest)
                        return
                    }
                }
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            case let ramp as RampAnnotation:
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectRamp?(ramp.ramp)
            case let c as CatchAnnotation where parent.onSelectCatch != nil:
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectCatch?(c.detail)
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

        /// The catches of an all-catch cluster, newest first, when they sit
        /// within a few metres of each other or the map is zoomed right in
        /// and they still collide. Nil when zooming in would split it.
        private static func inseparableCatches(_ members: [MKAnnotation], on map: MKMapView) -> [CatchDetail]? {
            let catches = members.compactMap { ($0 as? CatchAnnotation)?.detail }
            guard catches.count == members.count, catches.count > 1 else { return nil }
            guard PinClustering.spread(catches) < PinClustering.stackMetres
                    || map.region.span.latitudeDelta < 0.002 else { return nil }
            return catches.sorted { $0.catchRecord.caughtAt > $1.catchRecord.caughtAt }
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

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView,
                  let onLongPress = parent.onLongPress else { return }
            let point = gesture.location(in: map)
            onLongPress(map.convert(point, toCoordinateFrom: map))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
