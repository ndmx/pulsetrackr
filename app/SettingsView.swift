import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @AppStorage(AppStorageKey.watchRadius) private var watchRadius = 3.0
    @AppStorage(AppStorageKey.urgentAlerts) private var urgentAlerts = true
    @AppStorage(AppStorageKey.communityAlerts) private var communityAlerts = true
    @AppStorage(AppStorageKey.useApproximateLocation) private var useApproximateLocation = true

    // watchRadius is stored canonically in km; display it in the user's locale unit.
    private var radiusLabel: String {
        if Locale.current.measurementSystem != .metric {
            return String(format: "%.1f mi", watchRadius / 1.609_344)
        }
        return String(format: "%.1f km", watchRadius)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                watchAreaSection
                alertsSection
                sosSection
                privacySection
                statusSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(.black)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var watchAreaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: "Watch area")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Radius")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(radiusLabel)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Slider(value: $watchRadius, in: 1...15, step: 0.5)
                    .tint(.red)

                Text("Incidents within this range show in your feed and can trigger alerts.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .cardPanel()
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Alerts")
                .padding(.bottom, 14)

            SettingsToggleRow(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                label: "Urgent safety alerts",
                description: "Fires, armed incidents, medical emergencies",
                isOn: $urgentAlerts
            )

            Divider()
                .background(.white.opacity(0.07))
                .padding(.vertical, 12)

            SettingsToggleRow(
                icon: "person.3.fill",
                color: .blue,
                label: "Community notices",
                description: "Road blocks, outages, local warnings",
                isOn: $communityAlerts
            )
        }
        .cardPanel()
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: "Privacy")

            SettingsToggleRow(
                icon: "location.slash.fill",
                color: .teal,
                label: "Hide my exact location",
                description: "Others see only the general incident area, not where you are",
                isOn: $useApproximateLocation
            )

            Text("During SOS, exact location is shared with your trusted contacts only after you activate it. PulseTrackr does not automatically contact police, ambulance, or emergency services.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardPanel()
    }

    private var sosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: "SOS")

            NavigationLink {
                SOSTrustedContactsView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trusted contacts")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text(sosContactsDescription)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .buttonStyle(.plain)

            Divider()
                .background(.white.opacity(0.07))

            StatusRow(icon: "tray.and.arrow.up.fill", label: sosStore.uploadStatusText, color: sosStatusColor)
        }
        .cardPanel()
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeader(title: "App status")

            VStack(spacing: 10) {
                StatusRow(icon: "tray.full.fill", label: "Incident queue running", color: .green)
                StatusRow(icon: "checkmark.shield.fill", label: "Community verification active", color: .green)
                StatusRow(icon: "location.circle.fill", label: "Reporter locations protected", color: .green)
            }
        }
        .cardPanel()
    }

    private var sosContactsDescription: String {
        if sosStore.activeTrustedContacts.isEmpty {
            return "Add people before travel"
        }
        return "\(sosStore.activeTrustedContacts.count) ready for trusted-contact alerts"
    }

    private var sosStatusColor: Color {
        switch sosStore.deliveryState {
        case .failed: .orange
        case .syncing: .yellow
        case .delivered: .green
        case .localOnly, .ready: sosStore.activeTrustedContacts.isEmpty ? .orange : .green
        }
    }
}

struct SettingsSectionHeader: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.heavy)
            .foregroundStyle(.white.opacity(0.42))
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.red)
        }
    }
}

private struct StatusRow: View {
    var icon: String
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SOSStore())
    }
}
