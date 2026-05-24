#if canImport(MapboxMaps)
import CoreLocation
import MapboxMaps
import SwiftUI

struct FeedMapboxLayer: View {
    var incidents: [Incident]
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
        zoom: 14.7,
        bearing: -18,
        pitch: 44
    )

    var body: some View {
        Map(viewport: $viewport) {
            Puck2D(bearing: .heading)
                .showsAccuracyRing(true)

            ForEvery(incidents) { incident in
                MapViewAnnotation(coordinate: incident.coordinate) {
                    NavigationLink {
                        IncidentDetailView(incident: incident)
                    } label: {
                        FeedMapboxPin(incident: incident)
                    }
                    .buttonStyle(.plain)
                }
                .allowOverlap(true)
                .allowZElevate(true)
            }
        }
        .mapStyle(.standard(lightPreset: .night))
        .ornamentOptions(ornaments)
        .ignoresSafeArea()
    }

    private var ornaments: OrnamentOptions {
        var options = OrnamentOptions()
        options.logo.margins = CGPoint(x: 16, y: 90)
        options.attributionButton.margins = CGPoint(x: 16, y: 90)
        options.scaleBar.visibility = .hidden
        options.compass.visibility = .visible
        options.compass.margins = CGPoint(x: 16, y: 90)
        return options
    }
}

private struct FeedMapboxPin: View {
    var incident: Incident

    var body: some View {
        ZStack {
            Circle()
                .fill(incident.category.color.opacity(0.18))
                .frame(width: incident.isHighRisk ? 118 : 82, height: incident.isHighRisk ? 118 : 82)
                .overlay(
                    Circle()
                        .stroke(incident.category.color.opacity(0.20), lineWidth: 1)
                )

            Circle()
                .fill(.black.opacity(0.88))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(incident.category.color, lineWidth: 3))
                .shadow(color: incident.category.color.opacity(0.70), radius: 15)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(incident.category == .security || incident.category == .fire ? incident.category.color : .white)

            Image(systemName: incident.confidence.icon)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 17, height: 17)
                .background(incident.confidence.color, in: Circle())
                .offset(x: 19, y: -19)
        }
    }
}
#endif
