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

/// Moment-of-need rationale shown before the system location permission prompt.
struct LocationPermissionRationaleCard: View {
    var status: CLAuthorizationStatus
    var onRequestPermission: () -> Void
    var onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 48, height: 48)
                .background(DS.Color.accent.opacity(0.14), in: Circle())

            VStack(spacing: DS.Space.sm) {
                Text(title)
                    .font(DS.Font.cardTitle())
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(DS.Font.body())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Button(action: primaryAction) {
                Text(buttonTitle)
            }
            .buttonStyle(DSPrimaryButtonStyle())

            Button(action: onDismiss) {
                Text(secondaryButtonTitle)
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
        .pulsePanel()
    }

    private var iconName: String {
        switch status {
        case .denied, .restricted: "location.slash.fill"
        default: "location.fill.viewfinder"
        }
    }

    private var title: LocalizedStringKey {
        switch status {
        case .denied, .restricted: "Location access is off"
        default: "Use your location on the map"
        }
    }

    private var message: LocalizedStringKey {
        switch status {
        case .denied, .restricted:
            "Turn on location in Settings when you want PulseTrackr to center the map on you and show nearby reports."
        default:
            "PulseTrackr uses your location to center the map on you and show nearby reports in your watch area. You can keep browsing without sharing it."
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch status {
        case .denied, .restricted: "Open Settings"
        default: "Continue"
        }
    }

    private var secondaryButtonTitle: LocalizedStringKey {
        switch status {
        case .denied, .restricted: "Keep browsing"
        default: "Not now"
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

/// Compatibility wrapper for older call sites that still expect the previous
/// location prompt name.
struct LocationPromptCard: View {
    var status: CLAuthorizationStatus
    var onRequestPermission: () -> Void

    var body: some View {
        LocationPermissionRationaleCard(
            status: status,
            onRequestPermission: onRequestPermission,
            onDismiss: {}
        )
    }
}
