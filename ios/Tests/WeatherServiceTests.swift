import XCTest
@testable import Currents

final class WeatherServiceTests: XCTestCase {

    /// The hourly block Open-Meteo returns for `past_hours=6&forecast_hours=1`:
    /// six hours ago through this hour.
    private let sample = """
    {"hourly":{"time":["2026-10-24T19:00","2026-10-24T20:00","2026-10-24T21:00","2026-10-24T22:00","2026-10-24T23:00","2026-10-25T00:00","2026-10-25T01:00"],
    "pressure_msl":[1020.0,1020.1,1019.7,1018.8,1018.1,1018.0,1017.7]}}
    """

    private func hourly(_ json: String) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        return object?["hourly"] as? [String: Any]
    }

    func testPressureChangeIsNowMinusSixHoursAgo() throws {
        let change = WeatherService.pressureChange6h(hourly: try hourly(sample))
        XCTAssertEqual(change ?? 0, -2.3, accuracy: 0.001)
    }

    func testPressureChangeRisingIsPositive() throws {
        let json = """
        {"hourly":{"pressure_msl":[1008.0,1008.4,1009.0,1009.9,1010.5,1011.0,1011.2]}}
        """
        let change = WeatherService.pressureChange6h(hourly: try hourly(json))
        XCTAssertEqual(change ?? 0, 3.2, accuracy: 0.001)
    }

    func testShortSeriesGivesNoChange() throws {
        let json = """
        {"hourly":{"pressure_msl":[1012.0,1011.0]}}
        """
        XCTAssertNil(WeatherService.pressureChange6h(hourly: try hourly(json)))
        XCTAssertNil(WeatherService.pressureChange6h(hourly: nil))
    }
}
