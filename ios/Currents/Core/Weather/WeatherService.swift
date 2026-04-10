import Foundation
import CoreLocation

/// Fetches weather data from Open-Meteo API (free, no API key).
/// Falls back to cached/default data when offline.
actor WeatherService {
    static let shared = WeatherService()

    struct WeatherData: Sendable {
        let pressureHpa: Double
        let pressureChange6h: Double
        let temperatureC: Double
        let waterTempC: Double? // estimated from air temp for freshwater
        let windSpeedKmh: Double
        let windDirectionDeg: Double
        let cloudCoverPct: Int
        let precipMm: Double
        let condition: String // clear, cloudy, rain, storm, etc.
        let humidity: Int
        let uvIndex: Double
        let fetchedAt: Date
    }

    struct HourlyForecast: Sendable {
        let hours: [HourlyPoint]
    }

    struct HourlyPoint: Sendable {
        let date: Date
        let temperatureC: Double
        let pressureHpa: Double
        let windSpeedKmh: Double
        let windDirectionDeg: Double
        let precipMm: Double
        let cloudCoverPct: Int
    }

    private var cache: [String: (data: WeatherData, fetchedAt: Date)] = [:]

    /// Fetch current weather for a coordinate. Returns cached data if <30 min old or offline.
    func current(for coordinate: CLLocationCoordinate2D) async -> WeatherData? {
        let key = "\(Int(coordinate.latitude * 100))_\(Int(coordinate.longitude * 100))"

        // Return cache if fresh
        if let cached = cache[key], Date.now.timeIntervalSince(cached.fetchedAt) < 1800 {
            return cached.data
        }

        // Try fetching from Open-Meteo
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m,relative_humidity_2m,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,cloud_cover,precipitation,weather_code,uv_index&hourly=pressure_msl&forecast_hours=7&timezone=auto"

        guard let url = URL(string: urlString) else { return cache[key]?.data }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let current = json?["current"] as? [String: Any] else {
                return cache[key]?.data
            }

            let pressureNow = current["pressure_msl"] as? Double ?? current["surface_pressure"] as? Double ?? 1013.25
            let tempC = current["temperature_2m"] as? Double ?? 20
            let windSpeed = current["wind_speed_10m"] as? Double ?? 0
            let windDir = current["wind_direction_10m"] as? Double ?? 0
            let cloudCover = current["cloud_cover"] as? Int ?? 50
            let precip = current["precipitation"] as? Double ?? 0
            let humidity = current["relative_humidity_2m"] as? Int ?? 50
            let uvIndex = current["uv_index"] as? Double ?? 0
            let weatherCode = current["weather_code"] as? Int ?? 0

            // Compute 6h pressure change from hourly data
            var pressureChange6h = 0.0
            if let hourly = json?["hourly"] as? [String: Any],
               let pressures = hourly["pressure_msl"] as? [Double],
               pressures.count >= 7 {
                pressureChange6h = pressures.last! - pressures.first!
            }

            // Estimate water temp from air temp (rough freshwater heuristic)
            let waterTemp = tempC - 2.0

            let weather = WeatherData(
                pressureHpa: pressureNow,
                pressureChange6h: pressureChange6h,
                temperatureC: tempC,
                waterTempC: waterTemp,
                windSpeedKmh: windSpeed,
                windDirectionDeg: windDir,
                cloudCoverPct: cloudCover,
                precipMm: precip,
                condition: weatherCondition(code: weatherCode),
                humidity: humidity,
                uvIndex: uvIndex,
                fetchedAt: .now
            )

            cache[key] = (data: weather, fetchedAt: .now)
            return weather
        } catch {
            return cache[key]?.data
        }
    }

    /// Fetch hourly forecast for 48 hours
    func hourlyForecast(for coordinate: CLLocationCoordinate2D) async -> HourlyForecast? {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&hourly=temperature_2m,pressure_msl,wind_speed_10m,wind_direction_10m,precipitation,cloud_cover&forecast_days=2&timezone=auto"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let hourly = json?["hourly"] as? [String: Any],
                  let times = hourly["time"] as? [String],
                  let temps = hourly["temperature_2m"] as? [Double],
                  let pressures = hourly["pressure_msl"] as? [Double],
                  let winds = hourly["wind_speed_10m"] as? [Double],
                  let windDirs = hourly["wind_direction_10m"] as? [Double],
                  let precips = hourly["precipitation"] as? [Double],
                  let clouds = hourly["cloud_cover"] as? [Int] else {
                return nil
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

            var points: [HourlyPoint] = []
            for i in 0..<min(times.count, temps.count) {
                guard let date = formatter.date(from: times[i]) else { continue }
                points.append(HourlyPoint(
                    date: date,
                    temperatureC: temps[i],
                    pressureHpa: pressures[i],
                    windSpeedKmh: winds[i],
                    windDirectionDeg: windDirs[i],
                    precipMm: precips[i],
                    cloudCoverPct: clouds[i]
                ))
            }

            return HourlyForecast(hours: points)
        } catch {
            return nil
        }
    }

    private func weatherCondition(code: Int) -> String {
        switch code {
        case 0: return "clear"
        case 1, 2: return "partly cloudy"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51...57: return "drizzle"
        case 61...67: return "rain"
        case 71...77: return "snow"
        case 80...82: return "showers"
        case 85, 86: return "snow showers"
        case 95: return "storm"
        case 96, 99: return "thunderstorm"
        default: return "cloudy"
        }
    }
}
