import CoreLocation
import Foundation

/// Standard (David Troy / GeoFire-compatible) geohash encoding and neighbour
/// expansion, used to bound incident queries to the area around the user instead
/// of streaming every incident worldwide.
///
/// The server writes a precision-`writePrecision` geohash on each public incident.
/// The client picks a coarser precision sized to the query radius, then queries the
/// cell containing the user plus its 8 neighbours as prefix ranges. Results are then
/// distance-filtered exactly on the client.
enum Geohash {
    static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let base32Index: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (i, c) in base32.enumerated() { map[c] = i }
        return map
    }()

    /// Precision written to each incident document. Must be at least as fine as any
    /// query precision so prefix matching works.
    static let writePrecision = 9

    // MARK: - Encoding

    static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        var latInterval = (min: -90.0, max: 90.0)
        var lonInterval = (min: -180.0, max: 180.0)
        var hash = ""
        var isEven = true
        var bit = 0
        var ch = 0

        while hash.count < precision {
            if isEven {
                let mid = (lonInterval.min + lonInterval.max) / 2
                if longitude >= mid {
                    ch |= (1 << (4 - bit))
                    lonInterval.min = mid
                } else {
                    lonInterval.max = mid
                }
            } else {
                let mid = (latInterval.min + latInterval.max) / 2
                if latitude >= mid {
                    ch |= (1 << (4 - bit))
                    latInterval.min = mid
                } else {
                    latInterval.max = mid
                }
            }

            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                hash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
    }

    // MARK: - Neighbours

    private static let neighbourEven: [Direction: String] = [
        .right:  "bc01fg45238967deuvhjyznpkmstqrwx",
        .left:   "238967debc01fg45kmstqrwxuvhjyznp",
        .top:    "p0r21436x8zb9dcf5h7kjnmqesgutwvy",
        .bottom: "14365h7k9dcfesgujnmqp0r2twvyx8zb"
    ]
    private static let borderEven: [Direction: String] = [
        .right:  "bcfguvyz",
        .left:   "0145hjnp",
        .top:    "prxz",
        .bottom: "028b"
    ]

    private enum Direction { case top, bottom, left, right }

    private static func neighbourTable(_ dir: Direction, oddLength: Bool) -> String {
        // For odd-length geohashes the lat/lon bit orientation swaps, so a direction
        // maps to the perpendicular even-table (classic geohash-js derivation).
        guard oddLength else { return neighbourEven[dir]! }
        switch dir {
        case .bottom: return neighbourEven[.left]!
        case .top:    return neighbourEven[.right]!
        case .left:   return neighbourEven[.bottom]!
        case .right:  return neighbourEven[.top]!
        }
    }

    private static func borderTable(_ dir: Direction, oddLength: Bool) -> String {
        guard oddLength else { return borderEven[dir]! }
        switch dir {
        case .bottom: return borderEven[.left]!
        case .top:    return borderEven[.right]!
        case .left:   return borderEven[.bottom]!
        case .right:  return borderEven[.top]!
        }
    }

    private static func adjacent(_ hash: String, _ dir: Direction) -> String {
        guard let lastChar = hash.last else { return hash }
        let oddLength = hash.count % 2 == 1
        var base = String(hash.dropLast())

        if borderTable(dir, oddLength: oddLength).contains(lastChar), !base.isEmpty {
            base = adjacent(base, dir)
        }
        guard let index = neighbourTable(dir, oddLength: oddLength).firstIndex(of: lastChar) else {
            return hash
        }
        let position = neighbourTable(dir, oddLength: oddLength).distance(
            from: neighbourTable(dir, oddLength: oddLength).startIndex, to: index
        )
        return base + String(base32[position])
    }

    /// The 8 geohash cells surrounding `hash` (N, S, E, W and the four corners).
    static func neighbours(of hash: String) -> [String] {
        let north = adjacent(hash, .top)
        let south = adjacent(hash, .bottom)
        return [
            north,
            south,
            adjacent(hash, .left),
            adjacent(hash, .right),
            adjacent(north, .left),
            adjacent(north, .right),
            adjacent(south, .left),
            adjacent(south, .right)
        ]
    }

    // MARK: - Query bounds

    /// Smallest precision whose cell is at least as large as `radiusMeters` on its
    /// shorter side, so the 3×3 cell grid (centre + neighbours) covers the circle.
    static func precision(forRadiusMeters radius: Double) -> Int {
        switch radius {
        case ..<610:      return 6   // cell ≳ 0.6 km
        case ..<4_900:    return 5   // cell ≳ 4.9 km
        case ..<19_500:   return 4   // cell ≳ 19.5 km
        case ..<156_000:  return 3   // cell ≳ 156 km
        default:          return 2
        }
    }

    /// Geohash prefixes covering the circle: the centre cell plus its 8 neighbours,
    /// de-duplicated. Each prefix is queried as the range `[prefix, prefix + "~")`.
    static func coveringPrefixes(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) -> [String] {
        let precision = precision(forRadiusMeters: radiusMeters)
        let center = encode(latitude: latitude, longitude: longitude, precision: precision)
        var prefixes = Set([center])
        prefixes.formUnion(neighbours(of: center))
        return Array(prefixes)
    }

    /// The exclusive upper bound for a prefix range query. "~" sorts after every
    /// base32 character, so `[prefix, prefix + "~")` matches exactly the geohashes
    /// that start with `prefix`.
    static func rangeEnd(for prefix: String) -> String { prefix + "~" }
}
