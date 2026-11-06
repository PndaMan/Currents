import XCTest
import CoreLocation
@testable import Currents

final class TideEngineTests: XCTestCase {

    private let capeTown = CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    private let durban = CLLocationCoordinate2D(latitude: -29.87, longitude: 31.05)
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.75, longitude: -122.6)
    private let johannesburg = CLLocationCoordinate2D(latitude: -26.2, longitude: 28.04)

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// Values from the model that was scored against NOAA and tide gauges.
    func testHeightsMatchTheValidatedModel() throws {
        let expected: [(CLLocationCoordinate2D, TimeInterval, Double)] = [
            (capeTown, 1793923200, 0.46535), (capeTown, 1793944800, -0.50866),
            (capeTown, 1794000000, 0.10422), (capeTown, 1794100000, 0.55317),
            (durban, 1793923200, 0.44448), (durban, 1793944800, -0.54244),
            (durban, 1794000000, -0.03879), (durban, 1794100000, 0.58172),
            (sanFrancisco, 1793923200, -0.2673), (sanFrancisco, 1793944800, 0.14326),
            (sanFrancisco, 1794000000, -0.40922), (sanFrancisco, 1794100000, -0.50786),
        ]
        for (coordinate, seconds, height) in expected {
            let site = try XCTUnwrap(TideConstants.shared?.site(at: coordinate))
            XCTAssertEqual(site.relativeHeight(at: Date(timeIntervalSince1970: seconds)), height, accuracy: 0.001)
        }
    }

    /// NOAA's official times for San Francisco on 6 November 2026. The grid
    /// cell is off the Golden Gate, so it runs a little ahead of the station.
    func testHighAndLowLandOnPublishedTimes() {
        let days = ["2026-11-05T12:00:00Z", "2026-11-06T12:00:00Z", "2026-11-07T12:00:00Z"]
            .map { TideEngine.predict(date: date($0), coordinate: sanFrancisco) }
        let highs = days.flatMap(\.highTides)
        let lows = days.flatMap(\.lowTides)

        for text in ["2026-11-06T05:03:00Z", "2026-11-06T17:08:00Z"] {
            let official = date(text)
            XCTAssertTrue(highs.contains { abs($0.time.timeIntervalSince(official)) < 75 * 60 }, "No high near \(text)")
        }
        for text in ["2026-11-06T10:29:00Z", "2026-11-06T23:32:00Z"] {
            let official = date(text)
            XCTAssertTrue(lows.contains { abs($0.time.timeIntervalSince(official)) < 75 * 60 }, "No low near \(text)")
        }
    }

    func testHighsSitAboveLowsAndRisingLeadsToAHigh() throws {
        let day = TideEngine.predict(date: date("2026-11-06T12:00:00Z"), coordinate: capeTown)
        XCTAssertFalse(day.highTides.isEmpty)
        XCTAssertFalse(day.lowTides.isEmpty)
        let lowest = try XCTUnwrap(day.highTides.map(\.height).min())
        let highest = try XCTUnwrap(day.lowTides.map(\.height).max())
        XCTAssertGreaterThan(lowest, highest)

        let high = try XCTUnwrap(day.highTides.first)
        XCTAssertEqual(day.isRising(at: high.time.addingTimeInterval(-3600)), true)
        XCTAssertEqual(day.isRising(at: high.time.addingTimeInterval(3600)), false)
    }

    func testNoTideInland() {
        XCTAssertFalse(TideEngine.hasTide(at: johannesburg))
        XCTAssertTrue(TideEngine.hasTide(at: capeTown))

        let day = TideEngine.predict(date: date("2026-11-06T12:00:00Z"), coordinate: johannesburg)
        XCTAssertTrue(day.points.isEmpty)
        XCTAssertNil(day.isRising(at: date("2026-11-06T12:00:00Z")))
    }

    /// An inland day has no tide events, which must not trip the hourly scores.
    func testInlandForecastStillComputes() {
        let result = ForecastEngine.forecast(
            date: date("2026-11-06T12:00:00Z"), coordinate: johannesburg,
            currentPressureHpa: nil, pressureChange6h: nil, waterTempC: nil,
            windSpeedKmh: nil, windDirection: nil, species: nil, isInSpawningZone: false
        )
        XCTAssertEqual(result.hourlyScores.count, 24)
    }
}
