import Foundation
import CoreLocation

/// Finds places where an angler lingered during a session — likely fishing
/// spots worth saving. A "dwell" is a run of consecutive track points that stay
/// within `radius` metres for at least `minDwell` seconds.
enum SpotDetector {
    static func detectDwellSpots(in track: [Trip.TrackPoint],
                                 radius: Double = 45,
                                 minDwell: TimeInterval = 600) -> [CLLocationCoordinate2D] {
        guard track.count > 2 else { return [] }
        var spots: [CLLocationCoordinate2D] = []
        var anchorIdx = 0

        func closeCluster(_ endIdx: Int) {
            guard endIdx > anchorIdx else { return }
            let dwell = track[endIdx].t.timeIntervalSince(track[anchorIdx].t)
            guard dwell >= minDwell else { return }
            let slice = track[anchorIdx...endIdx]
            let lat = slice.map(\.lat).reduce(0, +) / Double(slice.count)
            let lon = slice.map(\.lon).reduce(0, +) / Double(slice.count)
            spots.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        for i in 1..<track.count {
            let anchor = CLLocation(latitude: track[anchorIdx].lat, longitude: track[anchorIdx].lon)
            let cur = CLLocation(latitude: track[i].lat, longitude: track[i].lon)
            if anchor.distance(from: cur) > radius {
                closeCluster(i - 1)
                anchorIdx = i
            }
        }
        closeCluster(track.count - 1)
        return mergeClose(spots, within: radius * 1.5)
    }

    private static func mergeClose(_ coords: [CLLocationCoordinate2D], within: Double) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for c in coords where !result.contains(where: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < within
        }) {
            result.append(c)
        }
        return result
    }
}
