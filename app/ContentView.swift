//
//  ContentView.swift
//  pulsetrackr
//
//  Created by Alexander Ukaga on 8/14/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var incidentStore = IncidentStore()
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab: AppTab = .map
    @AppStorage(AppStorageKey.hasSeenLaunch) private var hasSeenLaunch = false

    var body: some View {
        if hasSeenLaunch {
            mainTabs
        } else {
            LaunchView {
                withAnimation(.easeInOut(duration: 0.45)) {
                    hasSeenLaunch = true
                }
            }
        }
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
