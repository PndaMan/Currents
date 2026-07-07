import Foundation
import CoreMotion

/// Reads the iPhone's built-in barometer (CMAltimeter) so the bite forecast
/// still has a real, local air-pressure trend when there's no signal and the
/// weather cache is stale.
///
/// The absolute value is *station* pressure at the device's current altitude,
/// so it reads lower than sea-level pressure and is only approximate — but the
/// TREND (how it's changing over the last hours) is what drives feeding
/// behaviour, and that's what this captures reliably and offline. Samples are
/// persisted so the trend survives the app being backgrounded/relaunched.
@MainActor
final class BarometerService {
    static let shared = BarometerService()

    private let altimeter = CMAltimeter()
    private var samples: [Sample] = []
    private let maxAgeHours: Double = 8

    struct Sample: Codable { let t: Date; let hPa: Double }

    // Snapshot other components (WeatherService) can read without an actor hop.
    nonisolated static let pressureKey = "barometerPressureHpa"
    nonisolated static let changeKey = "barometerChange6h"
    nonisolated static let updatedKey = "barometerUpdatedAt"
    nonisolated static let spanHoursKey = "barometerSpanHours"

    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    private var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("barometer_samples.json")
    }

    func start() {
        guard isAvailable else { return }
        loadSamples()
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // CMAltitudeData.pressure is in kPa → hPa.
            let hPa = data.pressure.doubleValue * 10.0
            self.record(hPa)
        }
    }

    private func record(_ hPa: Double) {
        let now = Date()
        // Throttle to ~one stored sample every 2 minutes.
        if let last = samples.last, now.timeIntervalSince(last.t) < 120 { return }
        samples.append(Sample(t: now, hPa: hPa))
        let cutoff = now.addingTimeInterval(-maxAgeHours * 3600)
        samples.removeAll { $0.t < cutoff }
        saveSamples()
        publishSnapshot()
    }

    /// Current pressure + trend over the sampled window (up to 6h).
    private func publishSnapshot() {
        guard let latest = samples.last else { return }
        let sixHoursAgo = latest.t.addingTimeInterval(-6 * 3600)
        // Oldest sample within the 6h window (or the oldest we have).
        let ref = samples.first { $0.t >= sixHoursAgo } ?? samples.first!
        let spanHours = latest.t.timeIntervalSince(ref.t) / 3600
        let change = latest.hPa - ref.hPa
        let d = UserDefaults.standard
        d.set(latest.hPa, forKey: Self.pressureKey)
        d.set(change, forKey: Self.changeKey)
        d.set(latest.t.timeIntervalSince1970, forKey: Self.updatedKey)
        d.set(spanHours, forKey: Self.spanHoursKey)
    }

    private func loadSamples() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-maxAgeHours * 3600)
        samples = decoded.filter { $0.t >= cutoff }
    }

    private func saveSamples() {
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// A recent barometer reading for offline fallback, or nil if none/too old.
    struct Snapshot { let pressureHpa: Double; let change6h: Double; let spanHours: Double }
    nonisolated static func recentSnapshot(maxAge: TimeInterval = 3 * 3600) -> Snapshot? {
        let d = UserDefaults.standard
        let updated = d.double(forKey: updatedKey)
        guard updated > 0, Date().timeIntervalSince1970 - updated < maxAge else { return nil }
        let p = d.double(forKey: pressureKey)
        guard p > 800, p < 1100 else { return nil }
        return Snapshot(
            pressureHpa: p,
            change6h: d.double(forKey: changeKey),
            spanHours: d.double(forKey: spanHoursKey)
        )
    }
}
