#if canImport(MapboxMaps)
import CoreLocation
import MapboxMaps
import SwiftUI

struct FeedMapboxLayer: View {
    var incidents: [Incident]
    var userCoordinate: CLLocationCoordinate2D?

    @State private var hasCenteredOnUser = false

    // Only incidents with a known location can be pinned. Carrying the unwrapped
    // coordinate avoids optionals inside the Mapbox content builder.
    private struct MappableIncident: Identifiable {
        let incident: Incident
        let coordinate: CLLocationCoordinate2D
        var id: UUID { incident.id }
    }

    private var mappableIncidents: [MappableIncident] {
        incidents.compactMap { incident in
            incident.coordinate.map { MappableIncident(incident: incident, coordinate: $0) }
        }
    }

    @State private var viewport: Viewport = {
        if let last = LocationManager.lastKnownCoordinate {
            return .camera(center: last, zoom: 14.7, bearing: -18, pitch: 44)
        }
        // Brand-new user: open on a flat world view, not an arbitrary city.
        return .camera(center: MapDefaults.worldCenter, zoom: MapDefaults.worldMapboxZoom, bearing: 0, pitch: 0)
    }()

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                Map(viewport: $viewport) {
                    Puck2D(bearing: .heading)
                        .showsAccuracyRing(true)

                    ForEvery(mappableIncidents) { entry in
                        MapViewAnnotation(coordinate: entry.coordinate) {
                            NavigationLink {
                                IncidentDetailView(incident: entry.incident)
                            } label: {
                                FeedMapboxPin(incident: entry.incident)
                            }
                            .buttonStyle(.plain)
                        }
                        .allowOverlap(true)
                        .allowZElevate(true)
                    }
                }
                .mapStyle(.standard(lightPreset: .night))
                .ornamentOptions(ornaments)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
            } else {
                Color.black
            }
        }
        .onChange(of: userCoordinate?.latitude) { _, _ in centerOnUserOnce() }
        .onAppear { centerOnUserOnce() }
    }

    private func centerOnUserOnce() {
        guard !hasCenteredOnUser, let userCoordinate, userCoordinate.isValid else { return }
        hasCenteredOnUser = true
        withAnimation(.snappy) {
            viewport = .camera(center: userCoordinate, zoom: 14.7, bearing: -18, pitch: 44)
        }
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
                .fill(incident.severity.tint.opacity(0.18))
                .frame(width: incident.isHighRisk ? 118 : 82, height: incident.isHighRisk ? 118 : 82)
                .overlay(
                    Circle()
                        .stroke(incident.severity.tint.opacity(0.20), lineWidth: 1)
                )

            Circle()
                .fill(.black.opacity(0.88))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(incident.severity.tint, lineWidth: 3))
                .shadow(color: incident.severity.tint.opacity(0.70), radius: 15)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(.white)

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
