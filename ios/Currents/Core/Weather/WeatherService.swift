import Foundation
import CoreLocation

/// Fetches weather data from Open-Meteo API (free, no API key).
///
/// All responses are cached to DISK, so the last-known weather (current and
/// the 7-day outlook) keeps working offline — same philosophy as the map
/// tile cache. Fresh data replaces the cache whenever the network is back.
actor WeatherService {
    static let shared = WeatherService()

    struct WeatherData: Sendable, Codable {
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
    private var dailyCache: [String: (days: [WeatherData], fetchedAt: Date)] = [:]
    private var diskLoaded = false

    // MARK: - Disk persistence (offline access, like the tile cache)

    private struct DiskStore: Codable {
        var current: [String: WeatherData] = [:]
        var daily: [String: [WeatherData]] = [:]
    }

    private static var diskURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("weather_cache.json")
    }

    private func loadDiskIfNeeded() {
        guard !diskLoaded else { return }
        diskLoaded = true
        guard let data = try? Data(contentsOf: Self.diskURL),
              let store = try? JSONDecoder().decode(DiskStore.self, from: data) else { return }
        for (key, w) in store.current where cache[key] == nil {
            cache[key] = (w, w.fetchedAt)
        }
        for (key, days) in store.daily where dailyCache[key] == nil {
            dailyCache[key] = (days, days.first?.fetchedAt ?? .distantPast)
        }
    }

    private func persistToDisk() {
        var store = DiskStore()
        for (key, entry) in cache { store.current[key] = entry.data }
        for (key, entry) in dailyCache { store.daily[key] = entry.days }
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: Self.diskURL, options: .atomic)
        }
    }

    private static func cacheKey(_ coordinate: CLLocationCoordinate2D) -> String {
        "\(Int(coordinate.latitude * 100))_\(Int(coordinate.longitude * 100))"
    }

    /// Fetch current weather for a coordinate. Returns cached data if <30 min
    /// old; when the network is down, the last data ever fetched (any age,
    /// persisted across launches) is returned instead of nothing.
    func current(for coordinate: CLLocationCoordinate2D) async -> WeatherData? {
        loadDiskIfNeeded()
        let key = Self.cacheKey(coordinate)

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
            persistToDisk()
            return weather
        } catch {
            return cache[key]?.data
        }
    }

    /// Per-day weather for the next 7 days (index 0 = today), aggregated from
    /// Open-Meteo's hourly forecast: midday conditions, daylight-mean wind,
    /// the day's own pressure trend and precipitation total. Cached for an
    /// hour and persisted to disk so the outlook survives going offline.
    func forecastDays(for coordinate: CLLocationCoordinate2D) async -> [WeatherData] {
        loadDiskIfNeeded()
        let key = Self.cacheKey(coordinate)

        if let cached = dailyCache[key], Date.now.timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.days
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&hourly=temperature_2m,pressure_msl,wind_speed_10m,wind_direction_10m,precipitation,cloud_cover,relative_humidity_2m,weather_code,uv_index&forecast_days=7&timezone=auto"
        guard let url = URL(string: urlString) else { return dailyCache[key]?.days ?? [] }

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
                  let clouds = hourly["cloud_cover"] as? [Int],
                  let humidities = hourly["relative_humidity_2m"] as? [Int],
                  let codes = hourly["weather_code"] as? [Int],
                  let uvs = hourly["uv_index"] as? [Double] else {
                return dailyCache[key]?.days ?? []
            }

            let n = [times.count, temps.count, pressures.count, winds.count, windDirs.count,
                     precips.count, clouds.count, humidities.count, codes.count, uvs.count].min() ?? 0
            var days: [WeatherData] = []
            var day = 0
            while true {
                let start = day * 24
                guard start < n else { break }
                let end = min(start + 24, n)
                let range = start..<end
                // Midday sample (12:00) as the representative moment.
                let midday = min(start + 12, end - 1)
                // Daylight (06–20) mean wind — what an angler actually fishes in.
                let daylight = range.filter { ($0 - start) >= 6 && ($0 - start) <= 20 }
                let meanWind = daylight.isEmpty
                    ? winds[midday]
                    : daylight.map { winds[$0] }.reduce(0, +) / Double(daylight.count)
                // The day's own pressure trend: evening minus midday.
                let evening = min(start + 18, end - 1)
                let trend = pressures[evening] - pressures[midday]

                days.append(WeatherData(
                    pressureHpa: pressures[midday],
                    pressureChange6h: trend,
                    temperatureC: temps[midday],
                    waterTempC: temps[midday] - 2.0,
                    windSpeedKmh: meanWind,
                    windDirectionDeg: windDirs[midday],
                    cloudCoverPct: clouds[midday],
                    precipMm: range.map { precips[$0] }.reduce(0, +),
                    condition: weatherCondition(code: codes[midday]),
                    humidity: humidities[midday],
                    uvIndex: range.map { uvs[$0] }.max() ?? 0,
                    fetchedAt: .now
                ))
                day += 1
            }

            guard !days.isEmpty else { return dailyCache[key]?.days ?? [] }
            dailyCache[key] = (days, .now)
            persistToDisk()
            return days
        } catch {
            // Offline — serve the persisted outlook (any age) instead of nothing.
            return dailyCache[key]?.days ?? []
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
