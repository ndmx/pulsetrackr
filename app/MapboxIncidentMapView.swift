#if canImport(MapboxMaps)
import CoreLocation
import MapboxMaps
import SwiftUI

struct MapboxIncidentMapView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var sosStore: SOSStore
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @State private var selectedIncident: Incident?
    @State private var selectedCategory: IncidentCategory?
    @State private var isShowingCategoryFilters = false
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
        zoom: 15.1,
        bearing: -18,
        pitch: 44
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(viewport: $viewport) {
                Puck2D(bearing: .heading)
                    .showsAccuracyRing(true)

                ForEvery(sosStore.trailArtifacts) { artifact in
                    MapViewAnnotation(coordinate: artifact.coordinate) {
                        SOSTrailBreadcrumb(artifact: artifact)
                    }
                    .allowOverlap(true)
                    .allowZElevate(true)
                }

                if let lastKnownCoordinate = sosStore.lastKnownCoordinate {
                    MapViewAnnotation(coordinate: lastKnownCoordinate) {
                        SOSLastKnownMarker(
                            isActive: sosStore.isActive,
                            accuracy: sosStore.lastKnownPoint?.horizontalAccuracy
                        )
                    }
                    .allowOverlap(true)
                    .allowZElevate(true)
                }

                ForEvery(activeMapIncidents) { incident in
                    MapViewAnnotation(coordinate: incident.coordinate) {
                        NavigationLink {
                            IncidentDetailView(incident: incident)
                        } label: {
                            MapboxIncidentPin(incident: incident)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedIncident = incident
                        })
                    }
                    .allowOverlap(true)
                    .allowZElevate(true)
                }
            }
            .mapStyle(.standard(lightPreset: .night))
            .ornamentOptions(ornaments)
            .ignoresSafeArea(edges: .bottom)

            mapShade
            mapHeader
            mapSummary
            SOSOverlayView()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { locationManager.requestCurrentLocation() }
    }

    private var ornaments: OrnamentOptions {
        var options = OrnamentOptions()
        options.logo.margins = CGPoint(x: 16, y: 92)
        options.attributionButton.margins = CGPoint(x: 16, y: 92)
        options.scaleBar.visibility = .hidden
        options.compass.visibility = .visible
        options.compass.margins = CGPoint(x: 16, y: 92)
        return options
    }

    private var mapShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.26),
                Color.black.opacity(0.02),
                Color.black.opacity(0.70)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var mapHeader: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        isShowingCategoryFilters.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(selectedCategory?.label ?? "Incidents", systemImage: "square.3.layers.3d.down.right")
                            .font(.title3)
                            .fontWeight(.bold)

                        Image(systemName: isShowingCategoryFilters ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: focusOnUserLocation) {
                    Image(systemName: "location.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to my location")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if isShowingCategoryFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        CategoryChip(
                            title: "All",
                            icon: "circle.grid.2x2.fill",
                            color: .white,
                            isSelected: selectedCategory == nil,
                            darkBackground: true
                        ) {
                            selectedCategory = nil
                            selectedIncident = visibleIncidents.first
                        }

                        ForEach(IncidentCategory.allCases) { category in
                            CategoryChip(
                                title: category.label,
                                icon: category.icon,
                                color: category.color,
                                isSelected: selectedCategory == category,
                                darkBackground: true
                            ) {
                                selectedCategory = category
                                selectedIncident = activeMapIncidents.first { $0.category == category }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
    }

    private var mapSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom) {
                MapboxMetric(value: "\(urgentCount)", label: "Priority alerts", accent: .red)
                Spacer()
                MapboxMetric(value: "\(confirmedSightings)", label: "Confirmed sightings", detail: nearestDistanceText, accent: .cyan)
            }

            if let featuredIncident {
                NavigationLink {
                    IncidentDetailView(incident: featuredIncident)
                } label: {
                    MapboxFeaturedIncident(incident: featuredIncident)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var featuredIncident: Incident? {
        if let selectedIncident, activeMapIncidents.contains(selectedIncident) {
            return selectedIncident
        }

        return activeMapIncidents.first
    }

    private var visibleIncidents: [Incident] {
        incidentStore.nearbyIncidents(
            urgentAlerts: urgentAlerts,
            communityAlerts: communityAlerts,
            watchRadius: watchRadius,
            near: locationManager.currentCoordinate
        )
    }

    private var activeMapIncidents: [Incident] {
        guard let selectedCategory else { return visibleIncidents }
        return visibleIncidents.filter { $0.category == selectedCategory }
    }

    private var urgentCount: Int {
        activeMapIncidents.filter { $0.severity == .urgent || $0.severity == .high }.count
    }

    private var confirmedSightings: Int {
        activeMapIncidents.reduce(0) { $0 + $1.confirmations }
    }

    private var nearestDistanceText: String? {
        guard let userCoord = locationManager.currentCoordinate,
              let nearest = activeMapIncidents.min(by: {
                  $0.coordinate.distance(to: userCoord) < $1.coordinate.distance(to: userCoord)
              }) else { return nil }
        return "nearest \(userCoord.shortFormattedDistance(to: nearest.coordinate))"
    }

    private func focusOnUserLocation() {
        withAnimation(.snappy) {
            viewport = .followPuck(zoom: 15.1, bearing: .heading, pitch: 44)
        }
    }

}

private struct MapboxIncidentPin: View {
    var incident: Incident

    var body: some View {
        ZStack {
            IncidentDangerHalo(incident: incident)

            Circle()
                .fill(.black.opacity(0.88))
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(incident.category.color, lineWidth: 3))
                .shadow(color: incident.category.color.opacity(0.58), radius: 16)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: iconSize, weight: .heavy))
                .foregroundStyle(symbolColor)

            Image(systemName: incident.confidence.icon)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(incident.confidence.color, in: Circle())
                .offset(x: 20, y: -20)
        }
    }

    private var iconSize: CGFloat {
        incident.subtype == .gunshots ? 22 : 24
    }

    private var symbolColor: Color {
        incident.category == .security || incident.category == .fire ? incident.category.color : .white
    }
}

private struct MapboxMetric: View {
    var value: String
    var label: String
    var detail: String? = nil
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            }

            Text(detail.map { "\(label) • \($0)" } ?? label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct MapboxFeaturedIncident: View {
    var incident: Incident

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: incident.subtype.icon)
                .font(.headline)
                .foregroundStyle(incident.category.color)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.72), in: Circle())
                .overlay(Circle().stroke(incident.category.color, lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(incident.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(incident.confidence.rawValue) • \(incident.neighborhood)")
                    .font(.caption)
                    .foregroundStyle(incident.confidence.color.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.16), in: Circle())
        }
        .padding(12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

#endif
