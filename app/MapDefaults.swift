import MapKit
import SwiftUI

/// Shared initial-camera logic for every map. A returning user opens on their
/// last-known area; a brand-new user (no saved location) opens on a zoomed-out
/// world view rather than an arbitrary city, then the maps animate to the user
/// once the first GPS fix arrives.
enum MapDefaults {
    /// Roughly centres the landmasses for the pre-location world view.
    static let worldCenter = CLLocationCoordinate2D(latitude: 20, longitude: 0)
    static let worldSpan = MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)

    /// Mapbox zoom for the pre-location world view (≈ whole-world).
    static let worldMapboxZoom: Double = 1.4

    /// Whether we have any location to open on (saved or, by extension, live).
    static var hasKnownLocation: Bool { LocationManager.lastKnownCoordinate != nil }

    /// Initial MapKit camera: the user's last-known city view, or the world view.
    static func initialRegion(citySpan: MKCoordinateSpan) -> MapCameraPosition {
        if let last = LocationManager.lastKnownCoordinate {
            return .region(MKCoordinateRegion(center: last, span: citySpan))
        }
        return .region(MKCoordinateRegion(center: worldCenter, span: worldSpan))
    }
}
