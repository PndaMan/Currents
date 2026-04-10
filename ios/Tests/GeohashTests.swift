import XCTest
@testable import Currents

final class GeohashTests: XCTestCase {

    func testEncodeKnownLocation() {
        // Cape Town: -33.9249, 18.4241
        let hash = Geohash.encode(latitude: -33.9249, longitude: 18.4241, precision: 7)
        XCTAssertEqual(hash.count, 7)
        // Cape Town geohash starts with "k3"
        XCTAssertTrue(hash.hasPrefix("k3"), "Cape Town geohash should start with k3, got \(hash)")
    }

    func testEncodeNewYork() {
        let hash = Geohash.encode(latitude: 40.7128, longitude: -74.0060, precision: 5)
        XCTAssertEqual(hash.count, 5)
        XCTAssertTrue(hash.hasPrefix("dr5"), "NYC geohash should start with dr5, got \(hash)")
    }

    func testDecodeRoundTrip() {
        let lat = -33.9249
        let lon = 18.4241
        let hash = Geohash.encode(latitude: lat, longitude: lon, precision: 7)
        guard let decoded = Geohash.decode(hash) else {
            XCTFail("Failed to decode geohash")
            return
        }
        // Precision 7 should be within ~0.001 degrees
        XCTAssertEqual(decoded.latitude, lat, accuracy: 0.01)
        XCTAssertEqual(decoded.longitude, lon, accuracy: 0.01)
    }

    func testNeighborsCount() {
        let hash = Geohash.encode(latitude: 0, longitude: 0, precision: 5)
        let neighbors = Geohash.neighbors(of: hash)
        XCTAssertEqual(neighbors.count, 8, "Should have 8 neighbors")
    }

    func testNeighborsAreDistinct() {
        let hash = Geohash.encode(latitude: 40.0, longitude: -74.0, precision: 5)
        let neighbors = Geohash.neighbors(of: hash)
        let unique = Set(neighbors)
        XCTAssertEqual(unique.count, 8)
        XCTAssertFalse(unique.contains(hash), "Neighbors should not include center")
    }

    func testDecodeInvalidReturnsNil() {
        // 'a' is not in the base32 alphabet used by geohash
        XCTAssertNil(Geohash.decode("aaaa"))
    }

    func testPrecisionAffectsLength() {
        let h3 = Geohash.encode(latitude: 0, longitude: 0, precision: 3)
        let h7 = Geohash.encode(latitude: 0, longitude: 0, precision: 7)
        XCTAssertEqual(h3.count, 3)
        XCTAssertEqual(h7.count, 7)
        XCTAssertTrue(h7.hasPrefix(h3), "Higher precision should extend lower precision")
    }
}
