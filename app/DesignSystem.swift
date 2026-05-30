import SwiftUI
import UIKit

// MARK: - PulseTrackr Design System
//
// Direction: "Calm authority" — a restrained, infrastructural look.
//   • Near-black (dark) / near-white (light) neutral base + slate surfaces.
//   • ONE signal-red accent, reserved for genuine alerts and severity.
//   • Color is a meaning, not decoration: categories use muted identity tones,
//     severity uses a vivid alert ramp, everything else is neutral.
//   • A single token scale for spacing, radius, and type so screens stop
//     drifting apart.
//
// All colors are adaptive (light + dark) via dynamic UIColor providers, so the
// app reads correctly in both appearances without an asset catalog round-trip.

enum DS {

    // MARK: Spacing (4-pt rhythm)

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radius

    enum Radius {
        static let sm: CGFloat = 10   // inputs, small chips
        static let md: CGFloat = 14   // buttons, tiles
        static let lg: CGFloat = 20   // panels / cards
        static let pill: CGFloat = 999
    }

    // MARK: Hairline

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    // MARK: Semantic colors (adaptive)

    enum Color {
        /// App background — the lowest layer.
        static let background = SwiftUI.Color(light: 0xF3F5F8, dark: 0x0B0D10)
        /// Elevated surface — panels and cards sit on the background.
        static let surface = SwiftUI.Color(light: 0xFFFFFF, dark: 0x16191E)
        /// Nested surface — inputs and tiles sit on a panel.
        static let surfaceHigh = SwiftUI.Color(light: 0xEDEFF3, dark: 0x21262E)
        /// Hairline separators and panel strokes.
        static let hairline = SwiftUI.Color(light: 0xDCE0E6, dark: 0x2B313A)

        static let textPrimary = SwiftUI.Color(light: 0x0B0D10, dark: 0xF4F6F8)
        static let textSecondary = SwiftUI.Color(light: 0x5B626D, dark: 0xA6ADB7)
        static let textTertiary = SwiftUI.Color(light: 0x8B919B, dark: 0x6D7480)

        /// The one accent. Signal red — alerts, the primary report action, urgent.
        static let accent = SwiftUI.Color(light: 0xD11A2A, dark: 0xFF5A5F)
        static let accentSoft = SwiftUI.Color(light: 0xFBE9EB, dark: 0x2A1416)

        /// Positive / safe confirmation (kept calm, not neon).
        static let positive = SwiftUI.Color(light: 0x1E7A4D, dark: 0x4FBF87)
    }

    // MARK: Typography

    enum Font {
        static func screenTitle() -> SwiftUI.Font { .system(.largeTitle, design: .rounded, weight: .bold) }
        static func sectionTitle() -> SwiftUI.Font { .system(.subheadline, design: .rounded, weight: .semibold) }
        static func cardTitle() -> SwiftUI.Font { .system(.headline, design: .rounded, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(.subheadline) }
        static func caption() -> SwiftUI.Font { .system(.caption) }
        static func label() -> SwiftUI.Font { .system(.caption, weight: .semibold) }
    }
}

// MARK: - Adaptive color helper

extension Color {
    /// Build an adaptive color from two hex values (light + dark appearance).
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Panel (the single card surface)

extension View {
    /// The one card surface used across the app. Replaces the three divergent
    /// `detailPanel` / `reportPanel` / `settingsPanel` modifiers.
    func pulsePanel(padding: CGFloat = DS.Space.lg) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
    }
}

// MARK: - Section header (neutral — no per-section rainbow)

struct DSSectionHeader: View {
    var title: LocalizedStringKey
    var systemImage: String
    var optional: Bool = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
            Text(title)
                .font(DS.Font.sectionTitle())
                .foregroundStyle(DS.Color.textPrimary)
            if optional {
                Text("Optional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, 2)
                    .background(DS.Color.surfaceHigh, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Buttons

/// Primary call-to-action. Signal red — used sparingly (e.g. "Report now", SOS).
struct DSPrimaryButtonStyle: ButtonStyle {
    var tint: Color = DS.Color.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.cardTitle())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

/// Quiet secondary action — neutral surface, hairline border.
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.body().weight(.semibold))
            .foregroundStyle(DS.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(DS.Color.surfaceHigh.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
    }
}

// MARK: - Text field container

/// Neutral input surface shared by all text fields.
struct DSFieldContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(DS.Space.md)
            .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
    }
}

// MARK: - Severity ramp (the vivid alert palette)

extension IncidentSeverity {
    /// Vivid alert color — this is where saturated color is allowed to live.
    var tint: Color {
        switch self {
        case .urgent: DS.Color.accent
        case .high: Color(light: 0xD9610A, dark: 0xFF9F45)
        case .medium: Color(light: 0xB07D14, dark: 0xE7C45C)
        case .low: DS.Color.textSecondary
        }
    }

    var label: String { rawValue }
}

// MARK: - Severity badge

struct DSSeverityBadge: View {
    var severity: IncidentSeverity
    var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(severity.tint)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 3)
            .background(severity.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(severity.tint.opacity(0.32), lineWidth: 1))
    }
}
