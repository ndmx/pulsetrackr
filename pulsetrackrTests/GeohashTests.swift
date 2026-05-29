//
//  GeohashTests.swift
//  pulsetrackrTests
//
//  Validates the geohash encoding and neighbour expansion used to geo-bound the
//  incident feed. Correctness here is verified with a local decoder (round-trip
//  containment) and structural invariants, since the Firestore query path itself
//  can only be exercised against the emulator/live project.
//

import Testing
import CoreLocation
@testable import pulsetrackr

@Suite("Geohash")
struct GeohashTests {

    // Local reference decoder: returns the lat/lon bounding box a geohash represents.
    private func decodeBounds(_ hash: String) -> (latMin: Double, latMax: Double, lonMin: Double, lonMax: Double) {
        var lat = (-90.0, 90.0)
        var lon = (-180.0, 180.0)
        var isEven = true
        for ch in hash {
            guard let cd = Geohash.base32.firstIndex(of: ch) else { continue }
            for mask in [16, 8, 4, 2, 1] {
                if isEven {
                    let mid = (lon.0 + lon.1) / 2
                    if cd & mask != 0 { lon.0 = mid } else { lon.1 = mid }
                } else {
                    let mid = (lat.0 + lat.1) / 2
                    if cd & mask != 0 { lat.0 = mid } else { lat.1 = mid }
                }
                isEven.toggle()
            }
        }
        return (lat.0, lat.1, lon.0, lon.1)
    }

    private func center(of hash: String) -> CLLocationCoordinate2D {
        let b = decodeBounds(hash)
        return CLLocationCoordinate2D(latitude: (b.latMin + b.latMax) / 2, longitude: (b.lonMin + b.lonMax) / 2)
    }

    // MARK: - Encoding

    @Test func encodesKnownOrigin() {
        // (0,0) is the canonical "s0000…" cell.
        #expect(Geohash.encode(latitude: 0, longitude: 0, precision: 5) == "s0000")
    }

    @Test func encodedHashHasRequestedLength() {
        let hash = Geohash.encode(latitude: 6.5244, longitude: 3.3792, precision: 9)
        #expect(hash.count == 9)
    }

    @Test func encodedCellContainsItsPoint() {
        // For a spread of points and precisions, the decoded cell must contain the
        // original coordinate — the core correctness property of the encoder.
        let points = [
            (6.5244, 3.3792),     // Lagos
            (40.7484, -73.9857),  // New York
            (-33.8688, 151.2093), // Sydney
            (51.5074, -0.1278),   // London
            (0.0, 0.0),
            (-89.9, 179.9)        // near a corner
        ]
        for (lat, lon) in points {
            for precision in [4, 6, 9] {
                let hash = Geohash.encode(latitude: lat, longitude: lon, precision: precision)
                let b = decodeBounds(hash)
                #expect(lat >= b.latMin && lat <= b.latMax, "lat \(lat) outside cell at precision \(precision)")
                #expect(lon >= b.lonMin && lon <= b.lonMax, "lon \(lon) outside cell at precision \(precision)")
            }
        }
    }

    @Test func encodingIsDeterministic() {
        let a = Geohash.encode(latitude: 51.5, longitude: -0.12, precision: 8)
        let b = Geohash.encode(latitude: 51.5, longitude: -0.12, precision: 8)
        #expect(a == b)
    }

    // MARK: - Neighbours

    @Test func eightDistinctNeighbours() {
        let hash = Geohash.encode(latitude: 40.7484, longitude: -73.9857, precision: 6)
        let neighbours = Geohash.neighbours(of: hash)
        #expect(neighbours.count == 8)
        #expect(Set(neighbours).count == 8, "neighbours must be distinct")
        #expect(!neighbours.contains(hash), "the cell is not its own neighbour")
    }

    @Test func neighboursAreAdjacent() {
        // Each neighbour's centre must be within ~2 cell widths of the source centre.
        let hash = Geohash.encode(latitude: 48.8566, longitude: 2.3522, precision: 6)
        let origin = center(of: hash)
        let b = decodeBounds(hash)
        let cellHeight = (b.latMax - b.latMin)
        let cellWidth = (b.lonMax - b.lonMin)
        let maxDelta = max(cellHeight, cellWidth) * 2.0
        for neighbour in Geohash.neighbours(of: hash) {
            let c = center(of: neighbour)
            #expect(abs(c.latitude - origin.latitude) <= maxDelta + 1e-9)
            #expect(abs(c.longitude - origin.longitude) <= maxDelta + 1e-9)
        }
    }

    @Test func neighbourReciprocity() {
        // The right neighbour's left neighbour is the original cell, etc.
        let hash = Geohash.encode(latitude: 35.6895, longitude: 139.6917, precision: 7)
        let neighbours = Geohash.neighbours(of: hash)
        // Each neighbour should list `hash` among ITS neighbours.
        for neighbour in neighbours {
            #expect(Geohash.neighbours(of: neighbour).contains(hash),
                    "neighbour \(neighbour) should be reciprocal with \(hash)")
        }
    }

    // MARK: - Query bounds

    @Test func precisionShrinksWithRadius() {
        #expect(Geohash.precision(forRadiusMeters: 500) == 6)
        #expect(Geohash.precision(forRadiusMeters: 3_000) == 5)
        #expect(Geohash.precision(forRadiusMeters: 15_000) == 4)
        #expect(Geohash.precision(forRadiusMeters: 100_000) == 3)
    }

    @Test func coveringPrefixesIncludeCentreAndAtMostNine() {
        let prefixes = Geohash.coveringPrefixes(latitude: 6.5244, longitude: 3.3792, radiusMeters: 3_000)
        let center = Geohash.encode(latitude: 6.5244, longitude: 3.3792, precision: Geohash.precision(forRadiusMeters: 3_000))
        #expect(prefixes.contains(center))
        #expect(prefixes.count <= 9)
        #expect(Set(prefixes).count == prefixes.count, "prefixes must be unique")
    }

    @Test func coveringCircleIsContainedByPrefixCells() {
        // Every point on the query circle must fall inside one of the covering cells,
        // otherwise the query would miss incidents near the radius edge.
        let lat = 6.5244, lon = 3.3792, radius = 3_000.0
        let prefixes = Geohash.coveringPrefixes(latitude: lat, longitude: lon, radiusMeters: radius)
        let boxes = prefixes.map { decodeBounds($0) }
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = cos(lat * .pi / 180) * 111_320.0
        for degrees in stride(from: 0.0, to: 360.0, by: 30.0) {
            let rad = degrees * .pi / 180
            let pLat = lat + (radius * cos(rad) / metersPerDegLat)
            let pLon = lon + (radius * sin(rad) / metersPerDegLon)
            let covered = boxes.contains { pLat >= $0.latMin && pLat <= $0.latMax && pLon >= $0.lonMin && pLon <= $0.lonMax }
            #expect(covered, "circle point at \(degrees)° not covered by any prefix cell")
        }
    }

    @Test func rangeEndIsAboveAnyPrefixExtension() {
        let prefix = "s0000"
        let end = Geohash.rangeEnd(for: prefix)
        #expect(end > prefix)
        // Any real geohash extending the prefix sorts below the "~" sentinel end.
        #expect(prefix + "zzzz" < end)
        #expect(prefix + "0" < end)
    }
}
