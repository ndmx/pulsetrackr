import MapKit
import SwiftUI

struct IncidentMapView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @EnvironmentObject private var locationManager: LocationManager
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @State private var hasCenteredOnUser = false
    @State private var selectedIncident: Incident?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
            span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
        )
    )

    private var visibleIncidents: [Incident] {
        incidentStore.nearbyIncidents(
            urgentAlerts: urgentAlerts,
            communityAlerts: communityAlerts,
            watchRadius: watchRadius,
            near: locationManager.currentCoordinate
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(visibleIncidents) { incident in
                    Annotation(incident.title, coordinate: incident.coordinate) {
                        NavigationLink {
                            IncidentDetailView(incident: incident)
                        } label: {
                            LiveIncidentPin(incident: incident)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedIncident = incident
                        })
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .preferredColorScheme(.dark)

            mapShade

            mapSummary
        }
        .navigationTitle("Live Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.requestCurrentLocation()
        }
        .onReceive(locationManager.$currentCoordinate) { coordinate in
            guard let coordinate, !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }

    private var mapShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.42),
                Color.black.opacity(0.08),
                Color.black.opacity(0.58)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var mapSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(locationTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Immediate reports in your watch radius")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if urgentCount > 0 { LiveStatusPill(count: urgentCount) }
            }

            HStack(spacing: 12) {
                MapMetric(value: "\(visibleIncidents.count)", label: "active")
                MapMetric(value: "\(totalSightings)", label: "sightings")
                MapMetric(value: nearestDistanceText, label: "nearest")
            }

            if let featuredIncident {
                NavigationLink {
                    IncidentDetailView(incident: featuredIncident)
                } label: {
                    FeaturedIncidentCard(incident: featuredIncident)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .padding()
    }

    private var featuredIncident: Incident? {
        selectedIncident ?? visibleIncidents.first
    }

    private var urgentCount: Int {
        visibleIncidents.filter { $0.severity == .urgent || $0.severity == .high }.count
    }

    private var totalSightings: String {
        let total = visibleIncidents.reduce(0) { $0 + $1.confirmations }
        return total >= 1_000 ? String(format: "%.1fk", Double(total) / 1_000) : "\(total)"
    }

    private var nearestDistanceText: String {
        guard let userCoord = locationManager.currentCoordinate,
              let nearest = visibleIncidents.min(by: {
                  $0.coordinate.distance(to: userCoord) < $1.coordinate.distance(to: userCoord)
              }) else { return "—" }
        return userCoord.shortFormattedDistance(to: nearest.coordinate)
    }

    private var locationTitle: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.currentCoordinate == nil ? "Finding your location" : "You are here"
        case .denied, .restricted:
            "Location access off"
        case .notDetermined:
            "Enable location"
        @unknown default:
            "Nearby activity"
        }
    }
}

private struct LiveIncidentPin: View {
    var incident: Incident

    var body: some View {
        ZStack {
            Circle()
                .fill(incident.category.color.opacity(0.24))
                .frame(width: 74, height: 74)
                .blur(radius: 4)

            Circle()
                .stroke(incident.category.color.opacity(0.55), lineWidth: 2)
                .frame(width: 58, height: 58)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(iconColor)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.82), in: Circle())
                .overlay(
                    Circle()
                        .stroke(incident.category.color, lineWidth: 3)
                )
                .shadow(color: incident.category.color.opacity(0.65), radius: 14)
                .shadow(color: .black.opacity(0.55), radius: 7, y: 4)

            Image(systemName: incident.confidence.icon)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(incident.confidence.color, in: Circle())
                .offset(x: 20, y: -20)
        }
        .accessibilityLabel("\(incident.subtype.label): \(incident.title)")
    }

    private var iconColor: Color {
        incident.category == .security || incident.category == .fire ? incident.category.color : .white
    }
}

private struct LiveStatusPill: View {
    var count: Int

    var body: some View {
        Label("\(count)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.yellow, in: Capsule())
    }
}

private struct MapMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3)
                .fontWeight(.heavy)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeaturedIncidentCard: View {
    var incident: Incident

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: incident.subtype.icon)
                .font(.headline)
                .foregroundStyle(incident.category.color)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.72), in: Circle())
                .overlay(Circle().stroke(incident.category.color.opacity(0.75), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(incident.subtype.label)
                        .font(.caption2)
                        .textCase(.uppercase)
                        .fontWeight(.heavy)
                        .foregroundStyle(incident.category.color)
                    Text(incident.confidence.rawValue)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(incident.confidence.color)
                    Text(incident.reportedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.54))
                }
                Text(incident.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(incident.neighborhood)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        IncidentMapView()
            .environmentObject(IncidentStore())
            .environmentObject(LocationManager())
    }
}
