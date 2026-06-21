import MapKit
import SwiftUI

private enum FeedScope: String, CaseIterable, Identifiable {
    case all = "All"
    case priority = "Priority"
    case new = "New"
    case verified = "Verified"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "dot.radiowaves.left.and.right"
        case .priority: "exclamationmark.triangle.fill"
        case .new: "sparkles"
        case .verified: "checkmark.seal.fill"
        }
    }
}

private enum FeedSheetPosition {
    case collapsed
    case expanded
    case full

    func height(in availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .collapsed: 116
        case .expanded: min(370, availableHeight * 0.56)
        case .full: availableHeight
        }
    }
}

struct FeedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var incidentStore: IncidentStore
    @State private var selectedScope: FeedScope = .all
    @State private var selectedCategory: IncidentCategory?
    @State private var searchText = ""
    @State private var isShowingSearch = false
    @State private var isShowingFilters = true
    @State private var isMapExploreMode = false
    @State private var sheetPosition: FeedSheetPosition = .expanded
    @State private var sheetPositionBeforeMapExplore: FeedSheetPosition = .expanded
    @GestureState private var sheetDragOffset: CGFloat = 0
    @EnvironmentObject private var locationManager: LocationManager
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @State private var hasCenteredOnUser = false
    @State private var cameraPosition: MapCameraPosition = MapDefaults.initialRegion(
        citySpan: MKCoordinateSpan(latitudeDelta: 0.065, longitudeDelta: 0.065)
    )

    private var settingsFilteredIncidents: [Incident] {
        incidentStore.nearbyIncidents(
            urgentAlerts: urgentAlerts,
            communityAlerts: communityAlerts,
            watchRadius: watchRadius,
            near: locationManager.currentCoordinate
        )
    }

    private var scopedIncidents: [Incident] {
        switch selectedScope {
        case .all:
            settingsFilteredIncidents
        case .priority:
            settingsFilteredIncidents.filter { $0.isHighRisk }
        case .new:
            settingsFilteredIncidents.filter { $0.confidence == .unconfirmed || $0.reportedAt > Date().addingTimeInterval(-20 * 60) }
        case .verified:
            settingsFilteredIncidents.filter { $0.confidence == .communityVerified || $0.confidence == .officialUpdate }
        }
    }

    private var filteredIncidents: [Incident] {
        let categoryFiltered: [Incident]
        if let selectedCategory {
            categoryFiltered = scopedIncidents.filter { $0.category == selectedCategory }
        } else {
            categoryFiltered = scopedIncidents
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return categoryFiltered }

        return categoryFiltered.filter { incident in
            incident.title.lowercased().contains(query) ||
                incident.summary.lowercased().contains(query) ||
                incident.neighborhood.lowercased().contains(query) ||
                incident.category.label.lowercased().contains(query) ||
                incident.subtype.label.lowercased().contains(query)
        }
    }

    private var priorityCount: Int {
        settingsFilteredIncidents.filter { $0.isHighRisk }.count
    }

    private var headline: String {
        switch priorityCount {
        case 0:
            "No priority alerts nearby"
        case 1:
            "1 priority alert nearby"
        default:
            "\(priorityCount) priority alerts nearby"
        }
    }

    private func currentSheetHeight(in availableHeight: CGFloat) -> CGFloat {
        let proposedHeight = sheetPosition.height(in: availableHeight) - sheetDragOffset
        return min(max(proposedHeight, FeedSheetPosition.collapsed.height(in: availableHeight)), FeedSheetPosition.full.height(in: availableHeight))
    }

    private var mapOverlayColors: [Color] {
        if colorScheme == .dark {
            return [.black.opacity(0.50), .black.opacity(0.04), .black.opacity(0.94)]
        }
        return [.white.opacity(0.72), .white.opacity(0.08), DS.Color.background.opacity(0.96)]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                mapLayer
                    .allowsHitTesting(isMapExploreMode)

                LinearGradient(
                    colors: mapOverlayColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                topOverlay(sheetHeight: currentSheetHeight(in: proxy.size.height))
                feedControls

                bottomSheet(availableHeight: proxy.size.height)
            }
        }
        .background(DS.Color.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { locationManager.refreshCurrentLocationIfAuthorized() }
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

    @ViewBuilder
    private var mapLayer: some View {
        #if canImport(MapboxMaps)
        FeedMapboxLayer(
            incidents: settingsFilteredIncidents,
            userCoordinate: locationManager.currentCoordinate
        )
        #else
        appleMapLayer
        #endif
    }

    private var appleMapLayer: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            ForEach(settingsFilteredIncidents) { incident in
                if let coordinate = incident.coordinate {
                    Annotation(incident.title, coordinate: coordinate) {
                        NavigationLink {
                            IncidentDetailView(incident: incident)
                        } label: {
                            FeedMapPin(incident: incident)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(colorScheme == .dark ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
        .ignoresSafeArea()
    }

    private func topOverlay(sheetHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AROUND YOU")
                        .font(DS.Font.caption())
                        .fontWeight(.heavy)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Nearby area • Last 24 hours")
                        .font(DS.Font.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Color.textSecondary)
                }

                Spacer()
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(DS.Font.display(34, relativeTo: .largeTitle))
                    .tracking(-0.7)
                    .foregroundStyle(priorityCount > 0 ? DS.Color.alert : DS.Color.positive)
                    .lineLimit(2)

                Text(confirmedSightingsLabel)
                    .font(DS.Font.body())
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .opacity(sheetPosition == .full ? 0 : 1)
            // Sit a hair above the sheet top (sheetHeight) so the second line
            // clears the translucent sheet instead of tucking beneath it.
            .padding(.bottom, min(sheetHeight + 10, 420))
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .allowsHitTesting(false)
    }

    private var feedControls: some View {
        VStack {
            HStack {
                Spacer()

                HStack(spacing: 10) {
                    IconCircleButton(
                        icon: isMapExploreMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        accessibilityLabel: isMapExploreMode ? "Close interactive map" : "Explore interactive map",
                        isActive: isMapExploreMode
                    ) {
                        toggleMapExploreMode()
                    }

                    IconCircleButton(
                        icon: isShowingSearch ? "magnifyingglass.circle.fill" : "magnifyingglass",
                        accessibilityLabel: isShowingSearch ? "Hide search" : "Search feed"
                    ) {
                        withAnimation(.snappy) {
                            isShowingSearch.toggle()
                            if isShowingSearch {
                                sheetPosition = max(sheetPosition, .expanded)
                            } else {
                                searchText = ""
                            }
                        }
                    }

                    IconCircleButton(
                        icon: isShowingFilters ? "line.3.horizontal.decrease.circle.fill" : "slider.horizontal.3",
                        accessibilityLabel: isShowingFilters ? "Hide filters" : "Show filters"
                    ) {
                        withAnimation(.snappy) {
                            isShowingFilters.toggle()
                            if isShowingFilters {
                                sheetPosition = max(sheetPosition, .expanded)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Spacer()
        }
    }

    private func bottomSheet(availableHeight: CGFloat) -> some View {
        let sheetHeight = currentSheetHeight(in: availableHeight)
        let isFullEnough = sheetHeight > availableHeight * 0.78

        return VStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    switch sheetPosition {
                    case .collapsed:
                        sheetPosition = .expanded
                    case .expanded:
                        sheetPosition = .full
                    case .full:
                        sheetPosition = .collapsed
                    }
                }
            } label: {
                Capsule()
                    .fill(DS.Color.textTertiary.opacity(0.50))
                    .frame(width: 44, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isFullEnough {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AROUND YOU")
                            .font(DS.Font.caption2())
                            .fontWeight(.heavy)
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(headline)
                            .font(DS.Font.title3())
                            .fontWeight(.heavy)
                            .foregroundStyle(priorityCount > 0 ? DS.Color.alert : DS.Color.positive)
                            .lineLimit(2)
                    }

                    Spacer()

                    IconCircleButton(icon: "xmark", accessibilityLabel: "Collapse feed") {
                        withAnimation(.snappy) {
                            sheetPosition = .expanded
                        }
                    }
                }
            }

            if isShowingSearch {
                FeedSearchField(searchText: $searchText)
            }

            ScopeSelector(selectedScope: $selectedScope)

            if isShowingFilters && (sheetPosition != .collapsed || sheetHeight > 170) {
                categoryScroller
            }

            HStack {
                Text(sectionTitle)
                    .font(DS.Font.cardTitle())
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(filteredIncidents.count)")
                    .font(DS.Font.caption())
                    .fontWeight(.heavy)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DS.Color.surfaceHigh, in: Capsule())
            }

            if sheetPosition != .collapsed || sheetHeight > 225 {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if filteredIncidents.isEmpty {
                            EmptyFeedState()
                        } else {
                            ForEach(filteredIncidents) { incident in
                                NavigationLink {
                                    IncidentDetailView(incident: incident)
                                } label: {
                                    IncidentCard(incident: incident, userCoordinate: locationManager.currentCoordinate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: sheetHeight, alignment: .top)
        .clipped()
        .background(
            UnevenRoundedRectangle(topLeadingRadius: isFullEnough ? 0 : 26, topTrailingRadius: isFullEnough ? 0 : 26)
                .fill(DS.Color.surface.opacity(isFullEnough ? 0.98 : 0.92))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 24, y: -8)
        )
        .gesture(sheetDrag(availableHeight: availableHeight))
        .animation(.snappy, value: sheetPosition)
    }

    private func toggleMapExploreMode() {
        withAnimation(.snappy) {
            if isMapExploreMode {
                isMapExploreMode = false
                sheetPosition = sheetPositionBeforeMapExplore
            } else {
                sheetPositionBeforeMapExplore = sheetPosition
                isMapExploreMode = true
                isShowingSearch = false
                sheetPosition = .collapsed
            }
        }
    }

    private func sheetDrag(availableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($sheetDragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                withAnimation(.snappy) {
                    let projectedHeight = currentSheetHeight(in: availableHeight) - (value.predictedEndTranslation.height - value.translation.height)
                    let fullThreshold = availableHeight * 0.72
                    let expandedThreshold = (FeedSheetPosition.collapsed.height(in: availableHeight) + FeedSheetPosition.expanded.height(in: availableHeight)) / 2

                    if projectedHeight >= fullThreshold || value.translation.height < -90 {
                        sheetPosition = .full
                    } else if projectedHeight <= expandedThreshold || value.translation.height > 120 {
                        sheetPosition = .collapsed
                    } else {
                        sheetPosition = .expanded
                    }
                }
            }
    }

    private var sectionTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search results"
        }

        if let selectedCategory {
            return selectedCategory.label
        }

        return selectedScope == .all ? "Incidents" : selectedScope.rawValue
    }

    private var confirmedSightingsLabel: String {
        let total = settingsFilteredIncidents.reduce(0) { $0 + $1.confirmations }
        let radiusText = watchRadius < 1
            ? "\(Int(watchRadius * 1_000))m"
            : String(format: "%.0fkm", watchRadius)
        return "\(total) confirmed sightings within \(radiusText)"
    }

    private var categoryScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                CategoryChip(
                    title: "All",
                    icon: "circle.grid.2x2.fill",
                    color: DS.Color.textSecondary,
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(IncidentCategory.allCases) { category in
                    CategoryChip(
                        title: category.label,
                        icon: category.icon,
                        color: category.color,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

private func max(_ lhs: FeedSheetPosition, _ rhs: FeedSheetPosition) -> FeedSheetPosition {
    lhs.rank >= rhs.rank ? lhs : rhs
}

private extension FeedSheetPosition {
    var rank: Int {
        switch self {
        case .collapsed: 0
        case .expanded: 1
        case .full: 2
        }
    }
}

private struct FeedMapPin: View {
    var incident: Incident

    // Pin fill = severity (the heat-of-urgency read); icon inside = category identity.
    var body: some View {
        ZStack {
            Circle()
                .fill(incident.severity.tint.opacity(0.22))
                .frame(width: incident.isHighRisk ? 96 : 70, height: incident.isHighRisk ? 96 : 70)

            Circle()
                .fill(DS.Color.surface.opacity(0.94))
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(incident.severity.tint, lineWidth: 3))
                .shadow(color: incident.severity.tint.opacity(0.75), radius: 14)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(DS.Color.textPrimary)
        }
    }
}

private struct IconCircleButton: View {
    var icon: String
    var accessibilityLabel: String
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(isActive ? .white : DS.Color.textPrimary)
                .frame(width: 38, height: 38)
                .background(isActive ? DS.Color.accent : DS.Color.surface.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(isActive ? DS.Color.accent.opacity(0.55) : DS.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

private struct FeedSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.Color.textTertiary)

            TextField("Search incidents, areas, or types", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(DS.Color.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(DS.Color.hairline, lineWidth: 1)
        )
    }
}

private struct ScopeSelector: View {
    @Binding var selectedScope: FeedScope

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FeedScope.allCases) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    Label(scope.rawValue, systemImage: scope.icon)
                        .font(DS.Font.caption())
                        .fontWeight(.heavy)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedScope == scope ? DS.Color.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedScope == scope ? DS.Color.textPrimary : DS.Color.textTertiary)
            }
        }
        .padding(5)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: 14))
    }
}



private struct IncidentCard: View {
    var incident: Incident
    var userCoordinate: CLLocationCoordinate2D?

    private var distanceText: String {
        guard let userCoord = userCoordinate, let coord = incident.coordinate else {
            return incident.neighborhood
        }
        return userCoord.formattedDistance(to: coord)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: incident.subtype.icon)
                    .font(.headline)
                    .foregroundStyle(incident.category.color)
                    .frame(width: 42, height: 42)
                    .background(incident.category.color.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(incident.category.color.opacity(0.32), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(distanceText)
                            .foregroundStyle(DS.Color.textSecondary)
                        Text("•")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(incident.reportedAt, style: .relative)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .font(DS.Font.caption())
                    .fontWeight(.heavy)

                    Text(incident.title)
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)

                    Text(incident.neighborhood)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Spacer()

                DSSeverityBadge(severity: incident.severity)
            }

            HStack(spacing: DS.Space.sm) {
                InfoPill(icon: incident.confidence.icon, title: incident.confidence.rawValue, color: incident.confidence.color)
                InfoPill(icon: "eye.fill", title: "\(incident.confirmations)", color: DS.Color.textSecondary)
                if incident.isHighRisk {
                    InfoPill(icon: "bell.fill", title: "Alert sent", color: DS.Color.alert)
                }
            }
        }
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.hairline, lineWidth: 1)
        )
    }
}

private struct InfoPill: View {
    var icon: String
    var title: String
    var color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(DS.Font.caption2())
            .fontWeight(.heavy)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct EmptyFeedState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(DS.Color.positive)
            Text("Nothing active here")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
            Text("Try another filter or category.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FeedView()
            .environmentObject(IncidentStore.preview)
            .environmentObject(LocationManager())
    }
}
#endif
