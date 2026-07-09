import Foundation
import CoreLocation
import Observation

/// Owns the live fishing-session state and records a GPS breadcrumb while a
/// session is active. Background updates keep the track going with the phone in
/// a pocket (needs the `location` background mode, which is declared in
/// Info.plist). Persists incrementally so nothing is lost if the app is killed.
@MainActor
@Observable
final class TripTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var repository: TripRepository?

    private(set) var activeTrip: Trip?
    private(set) var track: [Trip.TrackPoint] = []
    private(set) var currentLocation: CLLocation?

    var isTracking: Bool { activeTrip != nil }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Wire up persistence and resume any session left running (app relaunch).
    func configure(repository: TripRepository) {
        self.repository = repository
        if activeTrip == nil, let active = (try? repository.fetchActive())?.first {
            activeTrip = active
            track = active.decodedTrack
            beginUpdates()
        }
    }

    @discardableResult
    func start(name: String, spotId: String?) -> Trip {
        var trip = Trip(name: name, startDate: .now, spotId: spotId)
        try? repository?.save(&trip)
        activeTrip = trip
        track = []
        beginUpdates()
        return trip
    }

    /// End the active session, saving its final track and end time.
    @discardableResult
    func end() -> Trip? {
        guard var trip = activeTrip else { return nil }
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        trip.endDate = .now
        trip.trackPoints = Trip.encodeTrack(track)
        try? repository?.save(&trip)
        activeTrip = nil
        track = []
        return trip
    }

    private func beginUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
        default:
            break
        }
        manager.startUpdatingLocation()
    }

    private func persistTrack() {
        guard var trip = activeTrip else { return }
        trip.trackPoints = Trip.encodeTrack(track)
        try? repository?.save(&trip)
        activeTrip = trip
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 60 else { return }
        Task { @MainActor in
            self.currentLocation = loc
            guard self.isTracking else { return }
            if let last = self.track.last {
                let moved = CLLocation(latitude: last.lat, longitude: last.lon).distance(from: loc)
                let elapsed = loc.timestamp.timeIntervalSince(last.t)
                if moved < 8 && elapsed < 15 { return }   // throttle
            }
            self.track.append(Trip.TrackPoint(lat: loc.coordinate.latitude,
                                              lon: loc.coordinate.longitude, t: loc.timestamp))
            if self.track.count % 5 == 0 { self.persistTrack() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.isTracking { self.beginUpdates() }
        }
    }
}
