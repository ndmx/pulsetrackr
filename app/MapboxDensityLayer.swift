#if canImport(MapboxMaps)
import CoreLocation
import MapboxMaps
import SwiftUI

/// GeoJSONSource + HeatmapLayer style content for incident density.
struct MapboxDensityLayer: MapStyleContent {
    var incidents: [Incident]
    var now: Date = Date()

    var body: some MapStyleContent {
        // Heatmap only covers data the client already has (watch-radius bounded).
        GeoJSONSource(id: "incident-density")
            .data(.featureCollection(featureCollection))

        HeatmapLayer(id: "incident-density-heat", source: "incident-density")
            .heatmapWeight(Exp(.get) { "w" })
            .heatmapRadius(Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                8
                12
                14
                28
            })
            .heatmapIntensity(Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                8
                0.6
                14
                1.4
            })
            .heatmapOpacity(Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                15.5
                0.55
                16.5
                0
            })
            .heatmapColor(Exp(.interpolate) {
                Exp(.linear)
                Exp(.heatmapDensity)
                0
                "rgba(0, 0, 0, 0)"
                0.35
                "rgba(231, 196, 92, 0.35)"
                0.7
                "rgba(255, 159, 69, 0.7)"
                1
                "rgba(255, 90, 95, 1)"
            })
    }

    private var featureCollection: FeatureCollection {
        let pairs = IncidentDensity.features(from: incidents, now: now)
        let features: [Feature] = pairs.map { pair in
            var feature = Feature(geometry: Point(pair.coordinate))
            feature.properties = ["w": .number(pair.weight)]
            return feature
        }
        return FeatureCollection(features: features)
    }
}

#endif
