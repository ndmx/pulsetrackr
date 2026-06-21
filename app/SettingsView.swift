import CoreLocation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var sosStore: SOSStore
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @AppStorage(AppStorageKey.lightModeEnabled) private var lightModeEnabled = false

    // watchRadius is stored canonically in km; display it in the user's locale unit.
    private var radiusLabel: String {
        if Locale.current.measurementSystem != .metric {
            return String(format: "%.1f mi", watchRadius / 1.609_344)
        }
        return String(format: "%.1f km", watchRadius)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                watchAreaSection
                appearanceSection
                alertsSection
                sosSection
                privacySection
                statusSection
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var watchAreaSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Watch area")

            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack {
                    Text("Radius")
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(radiusLabel)
                        .font(DS.Font.bodyBold())
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }

                Slider(value: $watchRadius, in: 1...15, step: 0.5)
                    .tint(DS.Color.accent)

                Text("Incidents within this range show in your feed and can trigger alerts.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .pulsePanel()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Appearance")

            SettingsToggleRow(
                icon: lightModeEnabled ? "sun.max.fill" : "moon.stars.fill",
                color: DS.Color.accent,
                label: "Light mode",
                description: "PulseTrackr opens in dark mode. Turn this on for a light theme.",
                isOn: $lightModeEnabled
            )

            Text("The live map and feed stay dark for legibility.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textTertiary)
        }
        .pulsePanel()
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Alerts")
                .padding(.bottom, DS.Space.md)

            SettingsToggleRow(
                icon: "exclamationmark.triangle.fill",
                color: DS.Color.accent,
                label: "Urgent safety alerts",
                description: "Show high-risk reports in your watch area",
                isOn: $urgentAlerts
            )

            Divider()
                .overlay(DS.Color.hairline)
                .padding(.vertical, DS.Space.md)

            SettingsToggleRow(
                icon: "person.3.fill",
                color: DS.Color.textSecondary,
                label: "Community notices",
                description: "Show lower-risk road, utility, weather, and local notices",
                isOn: $communityAlerts
            )

            Text("These filters apply to the feed and map inside your watch area.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textTertiary)
                .padding(.top, DS.Space.md)
        }
        .pulsePanel()
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Privacy")

            StatusRow(icon: "location.slash.fill", label: "Exact report locations protected", color: DS.Color.positive)

            Text("Public incident pins appear only as k-anonymous H3 areas after enough nearby reports.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(DS.Color.hairline)

            PrecisionLocationRow(
                title: preciseLocationTitle,
                detail: preciseLocationDetail,
                color: preciseLocationColor,
                showsSettingsButton: preciseLocationNeedsSettings
            )

            Text("During SOS, exact location is shared with your trusted contacts only after you activate it. PulseTrackr does not automatically contact police, ambulance, or emergency services.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pulsePanel()
    }

    private var sosSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "SOS")

            NavigationLink {
                SOSTrustedContactsView()
            } label: {
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 36, height: 36)
                        .background(DS.Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trusted contacts")
                            .font(DS.Font.bodyStrong())
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(sosContactsDescription)
                            .font(DS.Font.caption())
                            .foregroundStyle(DS.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(DS.Color.hairline)

            StatusRow(icon: "tray.and.arrow.up.fill", label: sosStore.uploadStatusText, color: sosStatusColor)
        }
        .pulsePanel()
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "App status")

            VStack(spacing: DS.Space.md) {
                StatusRow(icon: "tray.full.fill", label: "Incident queue running", color: DS.Color.positive)
                StatusRow(icon: "checkmark.shield.fill", label: "Community verification active", color: DS.Color.positive)
                StatusRow(icon: "location.circle.fill", label: "Reporter locations protected", color: DS.Color.positive)
            }
        }
        .pulsePanel()
    }

    private var sosContactsDescription: String {
        if sosStore.activeTrustedContacts.isEmpty {
            return "Add people before travel"
        }
        return "\(sosStore.activeTrustedContacts.count) ready for trusted-contact alerts"
    }

    private var sosStatusColor: Color {
        switch sosStore.deliveryState {
        case .failed: IncidentSeverity.high.tint
        case .syncing: IncidentSeverity.medium.tint
        case .delivered: DS.Color.positive
        case .localOnly, .ready: sosStore.activeTrustedContacts.isEmpty ? IncidentSeverity.high.tint : DS.Color.positive
        }
    }

    private var preciseLocationTitle: String {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            return "Precise Location unavailable"
        }

        switch locationManager.accuracyAuthorization {
        case .fullAccuracy:
            return "Precise Location on"
        case .reducedAccuracy:
            return "Precise Location off"
        @unknown default:
            return "Precise Location unknown"
        }
    }

    private var preciseLocationDetail: String {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            return "Allow location access in iOS Settings to enable watch-area alerts."
        }

        switch locationManager.accuracyAuthorization {
        case .fullAccuracy:
            return "iOS is allowing PulseTrackr to use full accuracy when needed."
        case .reducedAccuracy:
            return "iOS is sharing approximate location only; watch area and SOS may be less precise."
        @unknown default:
            return "iOS did not report the current accuracy mode."
        }
    }

    private var preciseLocationColor: Color {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            return IncidentSeverity.high.tint
        }
        return locationManager.accuracyAuthorization == .fullAccuracy ? DS.Color.positive : IncidentSeverity.high.tint
    }

    private var preciseLocationNeedsSettings: Bool {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            return true
        }
        return locationManager.accuracyAuthorization != .fullAccuracy
    }
}

struct SettingsSectionHeader: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(DS.Font.caption2Strong())
            .foregroundStyle(DS.Color.textTertiary)
            .kerning(1)
    }
}

private struct SettingsToggleRow: View {
    var icon: String
    var color: Color
    var label: String
    var description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Font.bodyStrong())
                    .foregroundStyle(DS.Color.textPrimary)
                Text(description)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(DS.Color.accent)
        }
    }
}

private struct StatusRow: View {
    var icon: String
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            Text(label)
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }
}

private struct PrecisionLocationRow: View {
    var title: String
    var detail: String
    var color: Color
    var showsSettingsButton: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.bodyStrong())
                    .foregroundStyle(DS.Color.textPrimary)
                Text(detail)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsSettingsButton {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iOS Settings")
                            .font(DS.Font.label())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.accent)
                    .padding(.top, DS.Space.xs)
                }
            }

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, DS.Space.md)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(LocationManager())
            .environmentObject(SOSStore())
    }
}
