import SwiftUI

struct ContentView: View {
    @StateObject private var incidentStore = IncidentStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var sosStore = SOSStore()
    @State private var selectedTab: AppTab = .map
    @State private var isShowingOpeningAnimation = true
    @AppStorage(AppStorageKey.hasSeenLaunch) private var hasSeenLaunch = false
    @AppStorage(AppStorageKey.launchLastSeenAt) private var launchLastSeenAt = 0.0
    @AppStorage(AppStorageKey.launchLastSeenVersion) private var launchLastSeenVersion = ""
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0

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
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.35)) {
                isShowingOpeningAnimation = false
            }
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
        withAnimation(.easeInOut(duration: 0.45)) {
            hasSeenLaunch = true
            launchLastSeenAt = Date().timeIntervalSince1970
            launchLastSeenVersion = currentAppVersion
        }
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
        .onReceive(locationManager.$currentLocation) { location in
            guard let location else { return }
            sosStore.record(location: location)
            incidentStore.updateObservedRegion(center: location.coordinate, radiusKm: watchRadius)
        }
        .onChange(of: watchRadius) { _, newRadius in
            guard let coordinate = locationManager.currentCoordinate else { return }
            incidentStore.updateObservedRegion(center: coordinate, radiusKm: newRadius)
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

#Preview {
    ContentView()
}
