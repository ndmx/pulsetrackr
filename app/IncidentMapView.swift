import MapKit
import SwiftUI

struct IncidentMapView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var sosStore: SOSStore
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @State private var hasCenteredOnUser = false
    @State private var selectedIncident: Incident?
    @State private var isShowingLocationRationale = false
    @State private var cameraPosition: MapCameraPosition = MapDefaults.initialRegion(
        citySpan: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
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
                if isLocationAuthorized {
                    UserAnnotation()
                }

                if sosStore.trail.count > 1 {
                    MapPolyline(coordinates: sosStore.trail.map(\.coordinate))
                        .stroke(.cyan.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                ForEach(sosStore.trailArtifacts) { artifact in
                    Annotation("Recent movement", coordinate: artifact.coordinate) {
                        SOSTrailBreadcrumb(artifact: artifact)
                    }
                }

                if let lastKnownCoordinate = sosStore.lastKnownCoordinate {
                    Annotation("Last known location", coordinate: lastKnownCoordinate) {
                        SOSLastKnownMarker(
                            isActive: sosStore.isActive,
                            accuracy: sosStore.lastKnownPoint?.horizontalAccuracy
                        )
                    }
                }

                ForEach(visibleIncidents) { incident in
                    if let coordinate = incident.coordinate {
                        Annotation(incident.title, coordinate: coordinate) {
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
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .preferredColorScheme(.dark)

            mapShade

            mapLocateButton
            mapSummary
            SOSOverlayView()
        }
        .overlay(alignment: .center) {
            if isShowingLocationRationale {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            isShowingLocationRationale = false
                        }
                    }

                LocationPermissionRationaleCard(
                    status: locationManager.authorizationStatus,
                    onRequestPermission: requestMapLocation,
                    onDismiss: dismissLocationRationale
                )
                .padding(32)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .navigationTitle("Live Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.refreshCurrentLocationIfAuthorized()
        }
        .onReceive(locationManager.$currentCoordinate) { coordinate in
            guard let coordinate, !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
    }

    private var isLocationAuthorized: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways
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

    private var mapLocateButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: focusOnUserLocation) {
                    Image(systemName: "location.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use my location on the map")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()
        }
    }

    private var mapSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(locationTitle)
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(.white)
                    Text("Immediate reports in your watch radius")
                        .font(DS.Font.body())
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
        guard let userCoord = locationManager.currentCoordinate else { return "—" }
        let located = visibleIncidents.compactMap { incident in
            incident.coordinate.map { (incident, $0) }
        }
        guard let nearest = located.min(by: {
            $0.1.distance(to: userCoord) < $1.1.distance(to: userCoord)
        }) else { return "—" }
        return userCoord.shortFormattedDistance(to: nearest.1)
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

    private func focusOnUserLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            withAnimation(.snappy) {
                isShowingLocationRationale = true
            }
        case .authorizedAlways, .authorizedWhenInUse:
            requestMapLocation()
            if let coordinate = locationManager.currentCoordinate ?? LocationManager.lastKnownCoordinate {
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                    )
                }
            }
        @unknown default:
            withAnimation(.snappy) {
                isShowingLocationRationale = true
            }
        }
    }

    private func requestMapLocation() {
        dismissLocationRationale()
        locationManager.requestCurrentLocation()
    }

    private func dismissLocationRationale() {
        withAnimation(.snappy) {
            isShowingLocationRationale = false
        }
    }
}

private struct LiveIncidentPin: View {
    var incident: Incident

    var body: some View {
        ZStack {
            IncidentDangerHalo(incident: incident)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.82), in: Circle())
                .overlay(
                    Circle()
                        .stroke(incident.severity.tint, lineWidth: 3)
                )
                .shadow(color: incident.severity.tint.opacity(0.65), radius: 14)
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
}

private struct LiveStatusPill: View {
    var count: Int

    var body: some View {
        Label("\(count)", systemImage: "exclamationmark.triangle.fill")
            .font(DS.Font.label())
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(DS.Color.alert, in: Capsule())
    }
}

private struct MapMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(DS.Font.title3())
                .fontWeight(.heavy)
                .foregroundStyle(.white)
            Text(label)
                .font(DS.Font.caption2())
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
                        .font(DS.Font.caption2())
                        .textCase(.uppercase)
                        .fontWeight(.heavy)
                        .foregroundStyle(incident.category.color)
                    Text(incident.confidenceLabel)
                        .font(DS.Font.caption2())
                        .fontWeight(.bold)
                        .foregroundStyle(incident.confidence.color)
                    Text(incident.reportedAt, style: .relative)
                        .font(DS.Font.caption2())
                        .foregroundStyle(.white.opacity(0.54))
                }
                Text(incident.title)
                    .font(DS.Font.body())
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(incident.neighborhood)
                    .font(DS.Font.caption())
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

#if DEBUG
#Preview {
    NavigationStack {
        IncidentMapView()
            .environmentObject(IncidentStore.preview)
            .environmentObject(LocationManager())
            .environmentObject(SOSStore())
    }
}
#endif
