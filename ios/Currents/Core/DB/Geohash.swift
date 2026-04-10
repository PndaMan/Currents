import Foundation

/// Pure-Swift geohash encoder/decoder for spatial indexing without PostGIS.
enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func encode(latitude: Double, longitude: Double, precision: Int = 7) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isEven = true
        var bit = 0
        var ch = 0
        var result = ""

        while result.count < precision {
            if isEven {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    ch |= (1 << (4 - bit))
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    ch |= (1 << (4 - bit))
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                result.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return result
    }

    static func decode(_ hash: String) -> (latitude: Double, longitude: Double)? {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isEven = true

        for char in hash {
            guard let idx = base32.firstIndex(of: char) else { return nil }
            for bit in stride(from: 4, through: 0, by: -1) {
                if isEven {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if idx & (1 << bit) != 0 {
                        lonRange.0 = mid
                    } else {
                        lonRange.1 = mid
                    }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if idx & (1 << bit) != 0 {
                        latRange.0 = mid
                    } else {
                        latRange.1 = mid
                    }
                }
                isEven.toggle()
            }
        }

        return (
            latitude: (latRange.0 + latRange.1) / 2,
            longitude: (lonRange.0 + lonRange.1) / 2
        )
    }

    /// Returns all neighbor geohashes at the same precision.
    static func neighbors(of hash: String) -> [String] {
        guard let center = decode(hash) else { return [] }
        let precision = hash.count
        // Approximate cell size for offset
        let latDelta = 180.0 / pow(2.0, Double(precision) * 2.5)
        let lonDelta = 360.0 / pow(2.0, Double(precision) * 2.5)

        var result: [String] = []
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let lat = center.latitude + Double(dy) * latDelta
                let lon = center.longitude + Double(dx) * lonDelta
                result.append(encode(latitude: lat, longitude: lon, precision: precision))
            }
        }
        return result
    }
}
