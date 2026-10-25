import SwiftUI
import MapKit

/// UIKit-backed map that renders the cacheable satellite tile overlay as the
/// base map. SwiftUI's `Map` cannot draw an `MKTileOverlay`, which is why the
/// tiles the app caches were never visible anywhere — this view is what makes
/// the cached map the *main* map: every tile fetched while online is served
/// from disk when there's no signal.
struct OfflineMapView: UIViewRepresentable {
    let overlay: OfflineTileOverlay
    /// The same clustered pins the standard and satellite maps show, drawn
    /// by the same SwiftUI views, so every map style looks alike.
    var pins: [PinCluster]
    var pinFace: (PinCluster) -> AnyView
    var onSelectPin: (PinCluster) -> Void
    /// Water drawn as a soft blue outline, as on the other styles.
    var waterOutlines: [Waterbody] = []
    /// The location marker the other styles use, in place of the blue dot.
    var userMarker: AnyView
    /// A region the parent asked for (a cluster zoom, framing a list); applied
    /// once each time it changes.
    var region: MKCoordinateRegion? = nil
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
    var onTap: (CLLocationCoordinate2D) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void
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

        context.coordinator.appliedRegion = region
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
        context.coordinator.apply(region, on: map)
        context.coordinator.syncAnnotations(on: map)
        context.coordinator.syncOverlays(on: map)
        context.coordinator.syncFlowFields(on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Annotations

    final class PinAnnotation: NSObject, MKAnnotation {
        var cluster: PinCluster
        var coordinate: CLLocationCoordinate2D { cluster.coordinate }
        init(cluster: PinCluster) {
            self.cluster = cluster
        }
    }

    /// An annotation view that shows a SwiftUI view, anchored like SwiftUI's
    /// `Annotation`: at its bottom centre for pins, at its centre for the
    /// location marker. Taps go to MapKit's selection, not the SwiftUI view.
    final class HostedAnnotationView: MKAnnotationView {
        static let reuseID = "hosted"
        private var host: UIHostingController<AnyView>?
        var anchorsAtBottom = true

        func show(_ content: AnyView) {
            if let host {
                host.rootView = content
            } else {
                let host = UIHostingController(rootView: content)
                host.view.backgroundColor = .clear
                host.view.isUserInteractionEnabled = false
                addSubview(host.view)
                self.host = host
            }
            guard let view = host?.view else { return }
            let size = view.sizeThatFits(UIView.layoutFittingExpandedSize)
            view.frame = CGRect(origin: .zero, size: size)
            frame.size = size
            centerOffset = CGPoint(x: 0, y: anchorsAtBottom ? -size.height / 2 : 0)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: OfflineMapView
        private var pinAnnotations: [String: PinAnnotation] = [:]
        private var waterFingerprint = ""
        /// Seeded with the region the map opened with, which is the parent's
        /// starting value rather than a request.
        var appliedRegion: MKCoordinateRegion?
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

        /// Moves the camera when the parent asks for a new region.
        func apply(_ region: MKCoordinateRegion?, on map: MKMapView) {
            guard let region else { return }
            if let last = appliedRegion,
               last.center.latitude == region.center.latitude,
               last.center.longitude == region.center.longitude,
               last.span.latitudeDelta == region.span.latitudeDelta,
               last.span.longitudeDelta == region.span.longitudeDelta { return }
            appliedRegion = region
            map.setRegion(region, animated: true)
        }

        /// Keeps one annotation per pin id, moving or redrawing it in place,
        /// so a pin's view (and its grow-in) survives a refresh.
        func syncAnnotations(on map: MKMapView) {
            var keep: Set<String> = []
            var added: [PinAnnotation] = []
            for cluster in parent.pins {
                keep.insert(cluster.id)
                if let existing = pinAnnotations[cluster.id] {
                    let moved = existing.coordinate.latitude != cluster.coordinate.latitude
                        || existing.coordinate.longitude != cluster.coordinate.longitude
                    if moved {
                        map.removeAnnotation(existing)
                        existing.cluster = cluster
                        added.append(existing)
                    } else {
                        existing.cluster = cluster
                        (map.view(for: existing) as? HostedAnnotationView)?.show(parent.pinFace(cluster))
                    }
                } else {
                    let annotation = PinAnnotation(cluster: cluster)
                    pinAnnotations[cluster.id] = annotation
                    added.append(annotation)
                }
            }
            let gone = pinAnnotations.filter { !keep.contains($0.key) }
            map.removeAnnotations(Array(gone.values))
            gone.keys.forEach { pinAnnotations[$0] = nil }
            map.addAnnotations(added)

            if let user = map.view(for: map.userLocation) as? HostedAnnotationView {
                user.show(parent.userMarker)
            }
            syncWater(on: map)
        }

        private func syncWater(on map: MKMapView) {
            let fp = parent.waterOutlines.map { "\($0.id ?? 0)" }.joined(separator: ",")
            guard fp != waterFingerprint else { return }
            waterFingerprint = fp
            map.removeOverlays(map.overlays.filter { $0 is MKCircle })
            map.addOverlays(parent.waterOutlines.map {
                MKCircle(center: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                         radius: CLLocationDistance(min($0.approximateRadiusM, 50000)))
            }, level: .aboveLabels)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor(Color.exploreWater.opacity(0.16))
                renderer.strokeColor = UIColor(Color.exploreWater.opacity(0.55))
                renderer.lineWidth = 1.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: HostedAnnotationView.reuseID)
                as? HostedAnnotationView)
                ?? HostedAnnotationView(annotation: annotation, reuseIdentifier: HostedAnnotationView.reuseID)
            view.annotation = annotation
            view.canShowCallout = false
            if annotation is MKUserLocation {
                view.anchorsAtBottom = false
                view.displayPriority = .required
                view.zPriority = .min
                view.show(parent.userMarker)
                return view
            }
            guard let pin = annotation as? PinAnnotation else { return nil }
            view.anchorsAtBottom = true
            view.displayPriority = .required
            view.zPriority = .defaultUnselected
            view.show(parent.pinFace(pin.cluster))
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            if let pin = annotation as? PinAnnotation {
                parent.onSelectPin(pin.cluster)
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

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView,
                  let onLongPress = parent.onLongPress else { return }
            let point = gesture.location(in: map)
            // A press held on a pin opens the pin, not a new spot under it.
            var hit = map.hitTest(point, with: nil)
            while let v = hit {
                if v is MKAnnotationView { return }
                hit = v.superview
            }
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
