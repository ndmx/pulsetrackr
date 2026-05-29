import CoreLocation
import SwiftUI
import UIKit

// MARK: - Card panel modifier

extension View {
    func cardPanel(backgroundOpacity: Double = 0.07) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    var title: String
    var icon: String
    var color: Color
    var isSelected: Bool
    var darkBackground: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? color.opacity(darkBackground ? 0.22 : 0.18)
                        : (darkBackground ? Color.black.opacity(0.46) : Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? color : .white.opacity(darkBackground ? 0.82 : 0.76))
                .overlay(
                    Capsule().stroke(
                        isSelected ? color.opacity(0.55) : .white.opacity(0.10),
                        lineWidth: darkBackground ? 1 : 0
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
        VStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
                .font(.title2)
                .foregroundStyle(.white)
            Text("See incidents near you")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.blue.opacity(0.22), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.blue.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .cardPanel()
    }

    // LocalizedStringKey (not String) so Text(_:) localizes via the String Catalog.
    private var message: LocalizedStringKey {
        switch status {
        case .denied, .restricted:
            "Location access is off, so the map can't show what's happening around you. Turn it on in Settings."
        default:
            "Turn on location to see live incidents and alerts in your area."
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
