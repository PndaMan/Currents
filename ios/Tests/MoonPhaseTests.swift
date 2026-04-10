import XCTest
@testable import Currents

final class MoonPhaseTests: XCTestCase {

    func testKnownNewMoon() {
        // Jan 6, 2000 was a known new moon
        let date = Date(timeIntervalSince1970: 947182440)
        let phase = MoonPhase.current(for: date)
        XCTAssertEqual(phase, .new)
    }

    func testFullMoonApprox14DaysLater() {
        // ~14.77 days after known new moon should be full
        let newMoon = Date(timeIntervalSince1970: 947182440)
        let fullDate = newMoon.addingTimeInterval(14.77 * 86400)
        let phase = MoonPhase.current(for: fullDate)
        XCTAssertEqual(phase, .full)
    }

    func testAllPhasesReachable() {
        // Walk through a full lunar cycle and collect all phases
        let start = Date(timeIntervalSince1970: 947182440)
        var seen = Set<MoonPhase>()
        for day in 0..<30 {
            let date = start.addingTimeInterval(Double(day) * 86400)
            seen.insert(MoonPhase.current(for: date))
        }
        XCTAssertEqual(seen.count, MoonPhase.allCases.count, "All 8 phases should occur in one lunar cycle")
    }

    func testDisplayNameNotEmpty() {
        for phase in MoonPhase.allCases {
            XCTAssertFalse(phase.displayName.isEmpty)
        }
    }

    func testSymbolNameNotEmpty() {
        for phase in MoonPhase.allCases {
            XCTAssertFalse(phase.symbolName.isEmpty)
        }
    }
}
