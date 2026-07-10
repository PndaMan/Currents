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
    /// True while a day within the active trip is being recorded. False when a
    /// multi-day trip is open but paused between days.
    private(set) var isDayActive = false
    /// True while auto-paused (stationary a while) — recording resumes on
    /// movement. Surfaced in the UI.
    private(set) var autoPaused = false
    private var pauseAnchor: CLLocation?
    private var stationaryStart: Date?

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
            // A day is active only if the trip has an open current day.
            isDayActive = active.currentDayStart != nil
            if isDayActive { beginUpdates() }
        }
    }

    @discardableResult
    func start(name: String, spotId: String?) -> Trip {
        var trip = Trip(name: name, startDate: .now, spotId: spotId, currentDayStart: .now)
        try? repository?.save(&trip)
        activeTrip = trip
        track = []
        isDayActive = true
        beginUpdates()
        beginLiveSession(trip)
        return trip
    }

    /// Begin a previously-planned session (clears its planned fields).
    @discardableResult
    func startPlanned(_ trip: Trip) -> Trip {
        var t = trip
        t.plannedDate = nil
        t.plannedLatitude = nil
        t.plannedLongitude = nil
        t.startDate = .now
        t.currentDayStart = .now
        try? repository?.save(&t)
        activeTrip = t
        track = []
        isDayActive = true
        beginUpdates()
        beginLiveSession(t)
        return t
    }

    /// Finish the current day but keep the trip open (multi-day). The day's
    /// track + times are archived; tracking pauses until `startNextDay()`.
    func endDay() {
        guard var trip = activeTrip, isDayActive else { return }
        var days = trip.decodedDays
        days.append(Trip.DayLog(index: days.count,
                                start: trip.currentDayStart ?? trip.startDate,
                                end: .now,
                                trackPoints: Trip.encodeTrack(track),
                                notes: nil))
        trip.days = Trip.encodeDays(days)
        trip.currentDayStart = nil
        trip.trackPoints = nil
        try? repository?.save(&trip)
        activeTrip = trip
        track = []
        isDayActive = false
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        NotificationManager.shared.cancelColdStreakNudge()
    }

    /// Start a new day within the already-open trip.
    func startNextDay() {
        guard var trip = activeTrip, !isDayActive else { return }
        trip.currentDayStart = .now
        try? repository?.save(&trip)
        activeTrip = trip
        track = []
        isDayActive = true
        resetAutoPause()
        beginUpdates()
        Task { await NotificationManager.shared.scheduleColdStreakNudge() }
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
        isDayActive = false
        NotificationManager.shared.cancelColdStreakNudge()
        LiveActivityManager.shared.end()
        WidgetSnapshotWriter.writeActiveSession(name: nil, start: nil, catches: 0)
        return trip
    }

    /// Kick off the Live Activity + widget snapshot for a newly-started session.
    private func beginLiveSession(_ trip: Trip) {
        resetAutoPause()
        LiveActivityManager.shared.start(sessionName: trip.name, startDate: trip.startDate, biteScore: 0)
        WidgetSnapshotWriter.writeActiveSession(name: trip.name, start: trip.startDate, catches: 0)
        Task { await NotificationManager.shared.scheduleColdStreakNudge() }
    }

    private func resetAutoPause() {
        autoPaused = false
        pauseAnchor = nil
        stationaryStart = nil
        manager.desiredAccuracy = kCLLocationAccuracyBest
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
            guard self.isTracking, self.isDayActive else { return }

            // Auto-pause: after being stationary a few minutes, stop recording
            // and drop to coarse accuracy (battery); resume on real movement.
            let movedFromAnchor = self.pauseAnchor.map { loc.distance(from: $0) } ?? .greatestFiniteMagnitude
            if movedFromAnchor > 30 {
                self.pauseAnchor = loc
                self.stationaryStart = nil
                if self.autoPaused {
                    self.autoPaused = false
                    self.manager.desiredAccuracy = kCLLocationAccuracyBest
                }
            } else {
                if self.stationaryStart == nil { self.stationaryStart = loc.timestamp }
                if let s = self.stationaryStart, loc.timestamp.timeIntervalSince(s) > 180 {
                    if !self.autoPaused {
                        self.autoPaused = true
                        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    }
                    return
                }
            }

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
