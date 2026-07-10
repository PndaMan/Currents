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
                Self.logQuickCatch()
            default:
                break
            }
            replyHandler(Self.stateDict())
        }
    }

    /// A minimal catch at the current location, auto-added to the active
    /// session — the angler fills in species/size later on the phone.
    @MainActor
    private static func logQuickCatch() {
        guard let app = AppState.shared else { return }
        let coord = app.locationManager.currentLocation?.coordinate
            ?? app.tripTracker.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var record = Catch(
            speciesId: nil,
            spotId: nil,
            caughtAt: .now,
            latitude: coord.latitude,
            longitude: coord.longitude,
            tripId: app.tripTracker.activeTrip?.id,
            notes: "Logged from Apple Watch"
        )
        try? app.catchRepository.save(&record)
    }
}
