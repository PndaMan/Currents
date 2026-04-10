import XCTest
@testable import Currents

final class ForecastEngineTests: XCTestCase {

    func testBaselineScoreWithNoData() {
        let result = ForecastEngine.compute(
            currentPressureHpa: nil,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: .firstQuarter,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        // With no data, all weights default to ~1.0, moon = 0.9
        XCTAssertGreaterThan(result.score, 0)
        XCTAssertLessThanOrEqual(result.score, 100)
    }

    func testFallingPressureBoostsScore() {
        let stable = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: 0,
            tidePhase: nil,
            moonPhase: .full,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        let falling = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: -5,
            tidePhase: nil,
            moonPhase: .full,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        XCTAssertGreaterThan(falling.score, stable.score, "Rapidly falling pressure should boost score")
    }

    func testSpawningZoneBoostsScore() {
        let noSpawn = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: .waxingCrescent,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        let spawning = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: .waxingCrescent,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: true
        )
        XCTAssertGreaterThan(spawning.score, noSpawn.score, "Spawning zone should boost score")
    }

    func testTideChangeBoostsScore() {
        let slack = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: nil,
            tidePhase: .slack,
            moonPhase: .waxingCrescent,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        let tideChange = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: nil,
            tidePhase: .nearHighOrLow,
            moonPhase: .waxingCrescent,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        XCTAssertGreaterThan(tideChange.score, slack.score)
    }

    func testFullMoonBoostsScore() {
        let quarter = ForecastEngine.compute(
            currentPressureHpa: nil,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: .firstQuarter,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        let full = ForecastEngine.compute(
            currentPressureHpa: nil,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: .full,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        XCTAssertGreaterThan(full.score, quarter.score)
    }

    func testScoreNeverExceeds100() {
        // Max all factors
        let result = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: -6,
            tidePhase: .nearHighOrLow,
            moonPhase: .full,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: true
        )
        XCTAssertLessThanOrEqual(result.score, 100)
        XCTAssertGreaterThanOrEqual(result.score, 0)
    }

    func testReasonsPopulated() {
        let result = ForecastEngine.compute(
            currentPressureHpa: 1005,
            pressureChange6h: -5,
            tidePhase: .nearHighOrLow,
            moonPhase: .full,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: true
        )
        XCTAssertFalse(result.reasons.isEmpty, "Should have explanatory reasons")
    }

    func testBreakdownValues() {
        let result = ForecastEngine.compute(
            currentPressureHpa: 1020,
            pressureChange6h: -3,
            tidePhase: .moving,
            moonPhase: .new,
            waterTempC: nil,
            species: nil,
            isInSpawningZone: false
        )
        XCTAssertEqual(result.breakdown.pressure, 1.0) // 1020 is in optimal range
        XCTAssertEqual(result.breakdown.pressureTrend, 1.3) // -3 is between -2 and -4
        XCTAssertEqual(result.breakdown.tide, 1.1) // moving tide
        XCTAssertEqual(result.breakdown.moon, 1.2) // new moon
        XCTAssertEqual(result.breakdown.season, 1.0) // not spawning
    }
}
