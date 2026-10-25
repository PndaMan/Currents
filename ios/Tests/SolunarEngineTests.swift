import XCTest
import CoreLocation
@testable import Currents

final class SolunarEngineTests: XCTestCase {

    /// Gordon's Bay, Western Cape, where the screenshots are taken.
    private let coordinate = CLLocationCoordinate2D(latitude: -34.235, longitude: 18.848)

    /// Moon overhead and underfoot fall roughly six hours from moonrise and
    /// moonset, so a major period never sits on a minor one. Checked for a
    /// lunar month from 24 October 2026, the day the overlap was seen.
    func testMajorPeriodsSitBetweenMoonriseAndMoonset() {
        let start = Date(timeIntervalSince1970: 1_792_843_200) // 24 Oct 2026, 12:00 UTC
        var checkedDays = 0

        for day in 0..<30 {
            let date = start.addingTimeInterval(Double(day) * 86400)
            let solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
            XCTAssertEqual(solunar.majorPeriods.count, 2, "Day \(day) should have moon overhead and underfoot")
            guard let moonrise = solunar.moonrise, let moonset = solunar.moonset else { continue }
            checkedDays += 1

            for major in solunar.majorPeriods {
                let hours = min(abs(major.peak.timeIntervalSince(moonrise)),
                                abs(major.peak.timeIntervalSince(moonset))) / 3600
                XCTAssertGreaterThan(hours, 4, "\(major.kind.rawValue) on day \(day) is \(hours) h from moonrise or moonset")
                XCTAssertLessThan(hours, 8, "\(major.kind.rawValue) on day \(day) is \(hours) h from moonrise or moonset")
            }
        }
        XCTAssertGreaterThan(checkedDays, 20)
    }

    /// Overhead and underfoot are half a lunar day apart.
    func testOverheadAndUnderfootAreHalfALunarDayApart() {
        let date = Date(timeIntervalSince1970: 1_792_843_200)
        let solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
        guard let overhead = solunar.majorPeriods.first(where: { $0.kind == .majorOverhead }),
              let underfoot = solunar.majorPeriods.first(where: { $0.kind == .majorUnderfoot }) else {
            return XCTFail("Both major periods should exist")
        }
        let hours = abs(overhead.peak.timeIntervalSince(underfoot.peak)) / 3600
        XCTAssertEqual(hours, 12.4, accuracy: 0.5)
        XCTAssertEqual(overhead.duration, 2 * 3600, accuracy: 1)
    }
}
