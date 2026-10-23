import SwiftUI

struct ContentView: View {
    @StateObject private var incidentStore = IncidentStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var sosStore = SOSStore()
    @State private var selectedTab: AppTab = .map
    @State private var deepLinkIncident: Incident?
    @State private var escortFollowAlert: SOSAppAlert?
    @AppStorage(AppStorageKey.hasSeenLaunch) private var hasSeenLaunch = false
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.lightModeEnabled) private var lightModeEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
        // New installs use Lumina's warm light canvas; an existing appearance
        // choice remains in AppStorage. The map keeps its operational styling.
        .preferredColorScheme(lightModeEnabled ? .light : .dark)
        .onOpenURL { url in
            guard case .incident(let id) = DeepLinkRouter.destination(for: url) else { return }
            selectedTab = .feed
            Task {
                deepLinkIncident = await incidentStore.incidentForDeepLink(id: id)
            }
        }
        .sheet(item: $deepLinkIncident) { incident in
            NavigationStack {
                IncidentDetailView(incident: incident)
            }
            .environmentObject(incidentStore)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasSeenLaunch {
            LaunchView {
                markWelcomeSeen()
            }
        } else {
            mainTabs
        }
    }

    private func markWelcomeSeen() {
        hasSeenLaunch = true
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PulseMapView()
            }
            .tabItem {
                Label("Map", systemImage: selectedTab == .map ? "map.fill" : "map")
            }
            .tag(AppTab.map)

            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Feed", systemImage: selectedTab == .feed ? "newspaper.fill" : "newspaper")
            }
            .tag(AppTab.feed)

            NavigationStack {
                ReportIncidentView()
            }
            .tabItem {
                Label("Report", systemImage: "plus.circle.fill")
            }
            .tag(AppTab.report)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape")
            }
            .tag(AppTab.settings)
        }
        .environmentObject(incidentStore)
        .environmentObject(locationManager)
        .environmentObject(sosStore)
        .overlay(alignment: .top) {
            if let alert = sosStore.activeAppAlert {
                SOSAppAlertBanner(alert: alert) {
                    if alert.kind == .escort {
                        escortFollowAlert = alert
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $escortFollowAlert) { alert in
            NavigationStack {
                EscortFollowView(initialAlert: alert)
                    .environmentObject(sosStore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                escortFollowAlert = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onReceive(locationManager.$currentLocation) { location in
            guard let location else { return }
            sosStore.record(location: location)
            incidentStore.updateObservedRegion(center: location.coordinate, radiusKm: watchRadius)
        }
        .onAppear {
            sosStore.startObservingAppAlerts()
            Task {
                try? await sosStore.refreshAppTrustedContacts()
                if sosStore.appTrustedContactList?.incoming.isEmpty == false {
                    SOSPushRegistration.requestPermissionAndRegister()
                }
            }
            incidentStore.retryPendingOutbox()
            sosStore.retryQueuedEvents()
        }
        .onChange(of: watchRadius) { _, newRadius in
            guard let coordinate = locationManager.currentCoordinate else { return }
            incidentStore.updateObservedRegion(center: coordinate, radiusKm: newRadius)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                try? await sosStore.refreshAppTrustedContacts()
                if sosStore.appTrustedContactList?.incoming.isEmpty == false {
                    SOSPushRegistration.requestPermissionAndRegister()
                }
            }
            incidentStore.retryPendingOutbox()
            sosStore.retryQueuedEvents()
        }
        .onReceive(sosStore.$session) { session in
            locationManager.setEmergencyTrackingActive(session?.isActive == true)
        }
    }
}

private enum AppTab {
    case map
    case feed
    case report
    case settings
}

private struct SOSAppAlertBanner: View {
    var alert: SOSAppAlert
    var onTap: (() -> Void)?

    private var isEscort: Bool { alert.kind == .escort }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: isEscort ? "figure.walk.circle.fill" : "sos.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(isEscort ? DS.Color.accent : DS.Color.alert, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(DS.Font.bodyBold())
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(locationText)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: DS.Space.sm)

                if isEscort {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DS.Color.textTertiary)
                        .padding(.top, 4)
                }
            }
            .padding(DS.Space.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke((isEscort ? DS.Color.accent : DS.Color.alert).opacity(0.42), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var titleText: String {
        if isEscort {
            return "\(alert.ownerDisplayName) is sharing a walk with you"
        }
        return "\(alert.ownerDisplayName) activated SOS"
    }

    private var locationText: String {
        if isEscort {
            guard let location = alert.lastKnownLocation else {
                return "Tap to follow their walk. This is not an emergency alert."
            }
            let latitude = String(format: "%.5f", location.latitude)
            let longitude = String(format: "%.5f", location.longitude)
            return "Latest location: \(latitude), \(longitude). Tap to open the walk trail."
        }

        guard let location = alert.lastKnownLocation else {
            return "Open PulseTrackr and try to contact them or local help. PulseTrackr does not dispatch responders."
        }

        let latitude = String(format: "%.5f", location.latitude)
        let longitude = String(format: "%.5f", location.longitude)
        return "Last phone location: \(latitude), \(longitude). Contact them or local help; PulseTrackr does not dispatch responders."
    }
}

#Preview {
    ContentView()
}
