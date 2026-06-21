import CoreLocation
import SwiftUI
import UIKit

// MARK: - Card panel modifier

extension View {
    /// Unified card surface. The `backgroundOpacity` argument is retained for
    /// source compatibility with existing call sites but is no longer used — every
    /// panel now resolves to the single `DS` surface so screens stay consistent.
    func cardPanel(backgroundOpacity: Double = 0.07) -> some View {
        pulsePanel()
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    var title: String
    var icon: String
    var color: Color
    var isSelected: Bool
    /// Retained for source compatibility; both map and feed chips now share the
    /// same adaptive surface, so the flag no longer changes styling.
    var darkBackground: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DS.Font.label())
                .lineLimit(1)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(
                    isSelected ? color.opacity(0.16) : DS.Color.surfaceHigh,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? color : DS.Color.textSecondary)
                .overlay(
                    Capsule().stroke(
                        isSelected ? color.opacity(0.5) : DS.Color.hairline,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location prompt

/// Region-neutral prompt shown when the app has no location to center on. Avoids
/// dropping users into an arbitrary city when location is undetermined or denied.
struct LocationPromptCard: View {
    var status: CLAuthorizationStatus
    /// Called for `.notDetermined` to trigger the system permission request.
    var onRequestPermission: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "location.slash.fill")
                .font(.title2)
                .foregroundStyle(DS.Color.textSecondary)
            Text("See incidents near you")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
            Text(message)
                .font(DS.Font.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Color.textSecondary)
            Button(action: primaryAction) {
                Text(buttonTitle)
            }
            .buttonStyle(DSSecondaryButtonStyle())
            .padding(.top, DS.Space.xs)
        }
        .pulsePanel()
    }

    // LocalizedStringKey (not String) so Text(_:) localizes via the String Catalog.
    private var message: LocalizedStringKey {
        switch status {
        case .denied, .restricted:
            "Location access is off, so the map can't show what's happening around you. Turn it on in Settings."
        default:
            "PulseTrackr uses your location to center the map and show nearby incidents in your watch area."
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch status {
        case .denied, .restricted: "Open Settings"
        default: "Enable location"
        }
    }

    private func primaryAction() {
        switch status {
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        default:
            onRequestPermission()
        }
    }
}
