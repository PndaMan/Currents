import Foundation
import WatchConnectivity
import CoreLocation

/// Phone side of the watch link. Answers the watch's state requests and runs
/// its quick actions (start/end session, log a catch) against the live
/// AppState. Bite score comes from the shared widget snapshot so replies are
/// instant (no async weather fetch inside the reply handler).
final class PhoneConnectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneConnectivity()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Push the latest session/bite state to the watch so its complication /
    /// UI stays fresh even without an explicit request.
    func pushState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        Task { @MainActor in
            let ctx = Self.stateDict()
            try? WCSession.default.updateApplicationContext(ctx)
        }
    }

    @MainActor
    private static func stateDict() -> [String: Any] {
        let app = AppState.shared
        let snap = SharedStore.load()
        var dict: [String: Any] = [
            WatchMessage.isTracking: app?.tripTracker.isTracking ?? false,
            WatchMessage.catchCount: snap?.activeSessionCatches ?? 0,
            WatchMessage.biteScore: snap?.biteScore ?? 0,
        ]
        if let trip = app?.tripTracker.activeTrip {
            dict[WatchMessage.sessionName] = trip.name
            dict[WatchMessage.sessionStart] = trip.startDate.timeIntervalSince1970
        }
        // Next planned trip → the "Next Trip" watch complication.
        if let name = snap?.nextSessionName, let date = snap?.nextSessionDate, date > .now {
            let f = DateFormatter()
            f.dateFormat = "EEE h a"
            dict[WatchMessage.nextPrimeWindow] = "\(name) · \(f.string(from: date))"
        }
        // Upcoming hourly bite scores so the watch face ticks on its own.
        if let hourly = snap?.hourly, !hourly.isEmpty {
            dict[WatchMessage.hourly] = hourly.map { [$0.date.timeIntervalSince1970, Double($0.score)] }
        }
        // Recent species → quick-log buttons on the watch.
        if let recent = try? app?.catchRepository.fetchAll(limit: 40) {
            var seen = Set<String>()
            let names = recent.compactMap { $0.species?.commonName }
                .filter { seen.insert($0).inserted }
                .prefix(6)
            if !names.isEmpty { dict[WatchMessage.recentSpecies] = Array(names) }
        }
        return dict
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message[WatchMessage.action] as? String ?? WatchMessage.requestState
        Task { @MainActor in
            switch action {
            case WatchMessage.startSession:
                if let app = AppState.shared, !app.tripTracker.isTracking {
                    _ = app.tripTracker.start(name: SessionFormat.defaultName(), spotId: nil)
                }
            case WatchMessage.endSession:
                _ = AppState.shared?.tripTracker.end()
            case WatchMessage.logCatch:
                Self.logQuickCatch(speciesName: message[WatchMessage.speciesName] as? String)
            default:
                break
            }
            replyHandler(Self.stateDict())
        }
    }

    /// A catch at the current location — with the species the angler named on
    /// the watch if it resolves. Works with or without an active session.
    @MainActor
    private static func logQuickCatch(speciesName: String?) {
        guard let app = AppState.shared else { return }
        let coord = app.locationManager.currentLocation?.coordinate
            ?? app.tripTracker.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let species = speciesName.flatMap { app.speciesRepository.resolve(spokenName: $0) }
        let note = speciesName.map { species == nil ? "Watch: \"\($0)\"" : "Logged from Apple Watch" }
            ?? "Logged from Apple Watch"
        var record = Catch(
            speciesId: species?.id,
            spotId: nil,
            caughtAt: .now,
            latitude: coord.latitude,
            longitude: coord.longitude,
            tripId: app.tripTracker.activeTrip?.id,
            notes: note
        )
        try? app.catchRepository.save(&record)
    }
}
