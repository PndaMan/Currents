import Foundation
import CoreLocation

/// A place inside an area that gets close-ups: a water body, or one of the
/// angler's spots, catches or planned sessions.
struct OfflineCloseUp: Sendable {
    let coordinate: CLLocationCoordinate2D
    let radiusKm: Double
    /// Surface area, so the biggest waters go first when the cap bites.
    var areaKm2: Double = 0

    /// Close-up for a water body from its surface area: the shore and a
    /// margin round it, a fixed reach for rivers and the coast (the bundled
    /// water is points, not outlines).
    static func water(_ w: Waterbody) -> OfflineCloseUp {
        let coord = CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude)
        switch w.type {
        case .river, .estuary, .coast:
            return OfflineCloseUp(coordinate: coord, radiusKm: 1.5, areaKm2: w.surfaceAreaKm2 ?? 0)
        case .dam, .lake:
            let area = w.surfaceAreaKm2 ?? 0
            let radius = min(max(0.6, 1.3 * sqrt(area / .pi)) + 0.4, 12)
            return OfflineCloseUp(coordinate: coord, radiusKm: radius, areaKm2: area)
        }
    }

    /// A spot, catch or planned session.
    static func place(_ coordinate: CLLocationCoordinate2D) -> OfflineCloseUp {
        OfflineCloseUp(coordinate: coordinate, radiusKm: 1.5, areaKm2: .infinity)
    }
}

/// What a download will fetch and roughly how big it is.
struct OfflinePlan: Sendable {
    var detail: OfflineDetail
    var overviewZoom: Int
    var closeUpZoom: Int
    var closeUps: [GeoRect]
    var watersIncluded: Int
    var watersAvailable: Int
    var placesIncluded: Int
    var tileCount: Int
    var estimatedBytes: Int64
    /// Some close-ups were left out to stay under the cap.
    var trimmed: Bool
    /// Over the cap even with nothing trimmable left (a square that is too big).
    var tooLarge: Bool
}

/// Works out which tiles an offline map needs. A region is saved at an
/// overview zoom over its outline, with full detail only around water and
/// the angler's own places inside it, because a whole province at full
/// detail would run to many gigabytes. A square is saved whole.
enum OfflinePlanner {
    static let minZoom = max(3, TileSources.current.minZoom)
    /// Overview tiles for a region, before its zoom steps down.
    static let overviewBudget = 4_000
    /// Most tiles in one offline map, set by the tile source (30,000 for
    /// satellite imagery is about 650 MB).
    static var tileCap: Int { TileSources.current.maxTilesPerDownload }
    static let maxZoom = 24

    /// Bytes for so many tiles at each zoom (`counts[z]`), from the source's
    /// typical tile sizes, times `scale` (how far real downloads from this
    /// source have come out from the estimates).
    static func estimate(_ counts: [Int], scale: Double) -> Int64 {
        let source = TileSources.current
        var bytes = 0.0
        for (z, n) in counts.enumerated() where n > 0 {
            bytes += Double(n) * Double(source.typicalTileBytes(zoom: z))
        }
        return Int64(bytes * scale)
    }

    /// The area being saved: a box, and for regions the outline inside it.
    struct Shape: Sendable {
        var bounds: GeoRect
        var rings: [[CLLocationCoordinate2D]] = []
        var areaKm2: Double
    }

    // MARK: Plans

    /// A square picked on the map, saved whole to the detail's zoom.
    static func areaPlan(_ rect: GeoRect, detail: OfflineDetail, scale: Double) -> OfflinePlan {
        let top = detail.closeUpZoom ?? min(14, TileSources.current.maxDownloadZoom)
        var counts = Array(repeating: 0, count: maxZoom + 1)
        for z in minZoom...top { counts[z] = TileMath.count(rect, z) }
        let count = counts.reduce(0, +)
        return OfflinePlan(detail: detail, overviewZoom: top, closeUpZoom: top, closeUps: [],
                           watersIncluded: 0, watersAvailable: 0, placesIncluded: 0,
                           tileCount: count, estimatedBytes: estimate(counts, scale: scale),
                           trimmed: false, tooLarge: count > tileCap)
    }

    /// A country or region: overview over the outline, then close-ups for
    /// the angler's places first and the biggest waters next, until the cap.
    static func regionPlan(_ shape: Shape, detail: OfflineDetail, places: [OfflineCloseUp],
                           waters: [OfflineCloseUp], scale: Double) -> OfflinePlan {
        let (overviewZoom, overview) = overviewTiles(shape)
        var counts = Array(repeating: 0, count: maxZoom + 1)
        for key in overview { counts[TileMath.unpack(key).z] += 1 }
        var total = overview.count
        guard let top = detail.closeUpZoom, top > overviewZoom else {
            return OfflinePlan(detail: detail, overviewZoom: overviewZoom, closeUpZoom: overviewZoom, closeUps: [],
                               watersIncluded: 0, watersAvailable: waters.count, placesIncluded: 0,
                               tileCount: total, estimatedBytes: estimate(counts, scale: scale),
                               trimmed: false, tooLarge: false)
        }
        var seen = Set<Int64>()
        var rects: [GeoRect] = []
        var placesIncluded = 0, watersIncluded = 0
        var trimmed = false
        let ordered = places.map { ($0, true) } + waters.sorted { $0.areaKm2 > $1.areaKm2 }.map { ($0, false) }
        for (closeUp, isPlace) in ordered {
            let rect = GeoRect(center: closeUp.coordinate, sideKm: closeUp.radiusKm * 2)
            var fresh: [(z: Int, keys: Set<Int64>)] = []
            var added = 0
            for z in (overviewZoom + 1)...top {
                // A set, as forEachTile can repeat a key across wrapped columns.
                var level = Set<Int64>()
                TileMath.forEachTile(in: closeUpRect(rect, z: z), z) { key in
                    if !seen.contains(key) { level.insert(key) }
                }
                fresh.append((z, level))
                added += level.count
            }
            if total + added > tileCap {
                trimmed = true
                break
            }
            for level in fresh {
                seen.formUnion(level.keys)
                counts[level.z] += level.keys.count
            }
            total += added
            rects.append(rect)
            if isPlace { placesIncluded += 1 } else { watersIncluded += 1 }
        }
        return OfflinePlan(detail: detail, overviewZoom: overviewZoom, closeUpZoom: top, closeUps: rects,
                           watersIncluded: watersIncluded, watersAvailable: waters.count,
                           placesIncluded: placesIncluded, tileCount: total,
                           estimatedBytes: estimate(counts, scale: scale), trimmed: trimmed, tooLarge: false)
    }

    /// Every tile a pack needs, lowest zoom first, the same each time for
    /// the same pack so a download can resume.
    static func tiles(for pack: OfflinePack, rings: [[CLLocationCoordinate2D]]) -> [Int64] {
        var keys = Set<Int64>()
        if pack.kind == .region {
            keys = maskedPyramid(Shape(bounds: pack.bounds, rings: rings, areaKm2: 0), top: pack.overviewZoom)
        } else {
            for z in minZoom...pack.overviewZoom {
                TileMath.forEachTile(in: pack.bounds, z) { keys.insert($0) }
            }
        }
        let top = min(pack.closeUpZoom, TileSources.current.maxDownloadZoom)
        if top > pack.overviewZoom {
            for rect in pack.closeUps {
                for z in (pack.overviewZoom + 1)...top {
                    TileMath.forEachTile(in: closeUpRect(rect, z: z), z) { keys.insert($0) }
                }
            }
        }
        // The cap holds even for a map planned under a looser source. Keys
        // sort by zoom, so the deepest tiles are the ones left out.
        return Array(keys.sorted().prefix(tileCap))
    }

    /// The deepest zooms reach less far from the centre, so the sharpest
    /// imagery is spread over more waters instead of one huge dam.
    static func closeUpRect(_ rect: GeoRect, z: Int) -> GeoRect {
        let reach: Double
        switch z {
        case ...14: return rect
        case 15: reach = 8
        case 16: reach = 5
        default: reach = 3
        }
        return rect.heightKm / 2 > reach ? GeoRect(center: rect.center, sideKm: reach * 2) : rect
    }

    // MARK: Overview

    /// The deepest overview zoom (5 to 14) that stays inside the budget, and
    /// its tiles. Guessed from the area first, then counted.
    static func overviewTiles(_ shape: Shape) -> (zoom: Int, tiles: Set<Int64>) {
        let lat = (shape.bounds.minLat + shape.bounds.maxLat) / 2
        let area = shape.areaKm2 > 0 ? shape.areaKm2 : shape.bounds.areaKm2
        var guess = 5
        for z in 5...max(5, min(14, TileSources.current.maxDownloadZoom)) {
            var estimate = 0.0
            for k in minZoom...z {
                let w = 40_075.016 * max(cos(lat * .pi / 180), 0.05) / Double(1 << k)
                estimate += area / (w * w) * 1.3 + 4
            }
            if estimate <= Double(overviewBudget) { guess = z }
        }
        var z = guess
        while true {
            let tiles = maskedPyramid(shape, top: z)
            if tiles.count <= overviewBudget || z <= 5 { return (z, tiles) }
            z -= 1
        }
    }

    /// Tiles touching the outline at `top`, plus every parent down to `minZoom`.
    static func maskedPyramid(_ shape: Shape, top: Int) -> Set<Int64> {
        var level = masked(shape, z: top)
        var all = level
        var z = top
        while z > minZoom {
            var parents = Set<Int64>()
            for key in level {
                let t = TileMath.unpack(key)
                parents.insert(TileMath.key(z - 1, t.x >> 1, t.y >> 1))
            }
            all.formUnion(parents)
            level = parents
            z -= 1
        }
        return all
    }

    /// Tiles at one zoom that the outline covers or crosses. Rows are filled
    /// between edge crossings at the row's middle, then the edges themselves
    /// are walked so thin capes and islands between row middles still count.
    static func masked(_ shape: Shape, z: Int) -> Set<Int64> {
        var keys = Set<Int64>()
        guard !shape.rings.isEmpty else {
            TileMath.forEachTile(in: shape.bounds, z) { keys.insert($0) }
            return keys
        }
        let y0 = TileMath.y(shape.bounds.maxLat, z), y1 = TileMath.y(shape.bounds.minLat, z)
        guard y1 >= y0 else { return keys }
        for ty in y0...y1 {
            let lat = TileMath.lat(ofY: Double(ty) + 0.5, z)
            for ring in shape.rings where ring.count > 2 {
                var crossings: [Double] = []
                var j = ring.count - 1
                for i in 0..<ring.count {
                    let a = ring[i], b = ring[j]
                    if (a.latitude > lat) != (b.latitude > lat) {
                        crossings.append(a.longitude + (lat - a.latitude) * (b.longitude - a.longitude) / (b.latitude - a.latitude))
                    }
                    j = i
                }
                crossings.sort()
                var k = 0
                while k + 1 < crossings.count {
                    let x0 = TileMath.x(crossings[k], z), x1 = TileMath.x(crossings[k + 1], z)
                    if x1 >= x0 {
                        for tx in x0...min(x1, x0 + (1 << z) - 1) {
                            keys.insert(TileMath.key(z, TileMath.wrap(tx, z), ty))
                        }
                    }
                    k += 2
                }
            }
        }
        let tileDeg = 360 / Double(1 << z)
        for ring in shape.rings where ring.count > 1 {
            for i in 0..<ring.count {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let step = tileDeg * 0.4 * max(cos(min(abs(a.latitude), 80) * .pi / 180), 0.17)
                let length = hypot(b.longitude - a.longitude, b.latitude - a.latitude)
                let n = max(Int(ceil(length / step)), 1)
                for s in 0...n {
                    let t = Double(s) / Double(n)
                    let lon = a.longitude + (b.longitude - a.longitude) * t
                    let lat = a.latitude + (b.latitude - a.latitude) * t
                    keys.insert(TileMath.key(z, TileMath.wrap(TileMath.x(lon, z), z), TileMath.y(lat, z)))
                }
            }
        }
        return keys
    }
}
