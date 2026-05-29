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
    @EnvironmentObject private var incidentStore: IncidentStore
    @State private var selectedScope: FeedScope = .all
    @State private var selectedCategory: IncidentCategory?
    @State private var searchText = ""
    @State private var isShowingSearch = false
    @State private var isShowingFilters = true
    @State private var sheetPosition: FeedSheetPosition = .expanded
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                mapLayer

                LinearGradient(
                    colors: [.black.opacity(0.50), .black.opacity(0.04), .black.opacity(0.94)],
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
        .background(.black)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear { locationManager.requestCurrentLocation() }
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
        .mapStyle(.hybrid(elevation: .realistic))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func topOverlay(sheetHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AROUND YOU")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    Text("Nearby area • Last 24 hours")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(priorityCount > 0 ? .red : .green)
                    .lineLimit(2)

                Text(confirmedSightingsLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.70))
            }
            .opacity(sheetPosition == .full ? 0 : 1)
            .padding(.bottom, min(sheetHeight - 15, 420))
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
                    .fill(.white.opacity(0.30))
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
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .foregroundStyle(.white.opacity(0.54))
                        Text(headline)
                            .font(.title3)
                            .fontWeight(.heavy)
                            .foregroundStyle(priorityCount > 0 ? .red : .green)
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
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(filteredIncidents.count)")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
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
                .fill(.black.opacity(isFullEnough ? 0.97 : 0.88))
                .shadow(color: .black.opacity(0.45), radius: 24, y: -8)
        )
        .gesture(sheetDrag(availableHeight: availableHeight))
        .animation(.snappy, value: sheetPosition)
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
                    color: .white,
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

    var body: some View {
        ZStack {
            Circle()
                .fill(incident.category.color.opacity(0.22))
                .frame(width: incident.isHighRisk ? 96 : 70, height: incident.isHighRisk ? 96 : 70)

            Circle()
                .fill(.black.opacity(0.86))
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(incident.category.color, lineWidth: 3))
                .shadow(color: incident.category.color.opacity(0.75), radius: 14)

            Image(systemName: incident.subtype.icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(incident.category == .security || incident.category == .fire ? incident.category.color : .white)
        }
    }
}

private struct IconCircleButton: View {
    var icon: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.54), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FeedSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.58))

            TextField("Search incidents, areas, or types", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.58))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
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
                        .font(.caption)
                        .fontWeight(.heavy)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selectedScope == scope ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedScope == scope ? .white : .white.opacity(0.58))
            }
        }
        .padding(5)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: incident.subtype.icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(incident.category.color, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(distanceText)
                            .foregroundStyle(incident.category.color)
                        Text("•")
                            .foregroundStyle(.white.opacity(0.38))
                        Text(incident.reportedAt, style: .relative)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    .font(.caption)
                    .fontWeight(.heavy)

                    Text(incident.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(incident.neighborhood)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.top, 14)
            }

            HStack(spacing: 8) {
                InfoPill(icon: incident.confidence.icon, title: incident.confidence.rawValue, color: incident.confidence.color)
                InfoPill(icon: "eye.fill", title: "\(incident.confirmations)", color: .white.opacity(0.72))
                if incident.isHighRisk {
                    InfoPill(icon: "bell.fill", title: "Alert sent", color: .red)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct InfoPill: View {
    var icon: String
    var title: String
    var color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2)
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
                .foregroundStyle(.green)
            Text("Nothing active here")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Try another filter or category.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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
