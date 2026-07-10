import SwiftUI

struct ContentView: View {
    @StateObject private var incidentStore = IncidentStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var sosStore = SOSStore()
    @State private var selectedTab: AppTab = .map
    @State private var deepLinkIncident: Incident?
    @State private var isShowingOpeningAnimation = true
    @AppStorage(AppStorageKey.hasSeenLaunch) private var hasSeenLaunch = false
    @AppStorage(AppStorageKey.launchLastSeenAt) private var launchLastSeenAt = 0.0
    @AppStorage(AppStorageKey.launchLastSeenVersion) private var launchLastSeenVersion = ""
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.lightModeEnabled) private var lightModeEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    private let welcomeResetInterval: TimeInterval = 30 * 24 * 60 * 60

    var body: some View {
        ZStack {
            content
                .opacity(isShowingOpeningAnimation ? 0 : 1)

            if isShowingOpeningAnimation {
                OpeningSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Declare the scheme at the root so the very first frame is dark (no
        // system-light flash on launch). Default is dark; the Settings toggle
        // opts into light. The immersive map/feed screens keep their own dark
        // override regardless, since they're built on a dark map surface.
        .preferredColorScheme(lightModeEnabled ? .light : .dark)
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.35)) {
                isShowingOpeningAnimation = false
            }
        }
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
        if shouldShowWelcome {
            LaunchView {
                markWelcomeSeen()
            }
        } else {
            mainTabs
        }
    }

    private var shouldShowWelcome: Bool {
        guard hasSeenLaunch else { return true }
        guard launchLastSeenVersion == currentAppVersion else { return true }
        guard launchLastSeenAt > 0 else { return true }
        return Date().timeIntervalSince1970 - launchLastSeenAt >= welcomeResetInterval
    }

    private func markWelcomeSeen() {
        // Set the flags directly (no withAnimation): the LaunchView runs a
        // `.repeatForever` pulse, and animating the LaunchView → mainTabs identity
        // swap while that transaction is live can wedge the transition and freeze
        // the UI. A plain state change swaps in the tabs immediately and reliably.
        hasSeenLaunch = true
        launchLastSeenAt = Date().timeIntervalSince1970
        launchLastSeenVersion = currentAppVersion
    }

    private var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version)-\(build)"
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
                SOSAppAlertBanner(alert: alert)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(locationManager.$currentLocation) { location in
            guard let location else { return }
            sosStore.record(location: location)
            incidentStore.updateObservedRegion(center: location.coordinate, radiusKm: watchRadius)
        }
        .onAppear {
            sosStore.startObservingAppAlerts()
            incidentStore.retryPendingOutbox()
            sosStore.retryQueuedEvents()
        }
        .onChange(of: watchRadius) { _, newRadius in
            guard let coordinate = locationManager.currentCoordinate else { return }
            incidentStore.updateObservedRegion(center: coordinate, radiusKm: newRadius)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
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

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "sos.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(DS.Color.alert, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("\(alert.ownerDisplayName) activated SOS")
                    .font(DS.Font.bodyBold())
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)

                Text(locationText)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DS.Space.sm)
        }
        .padding(DS.Space.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.alert.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
    }

    private var locationText: String {
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
