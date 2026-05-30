import SwiftUI
import UIKit

// MARK: - PulseTrackr Design System
//
// Brand source of truth: @xlumina/system (the Lumina design-system package).
// PulseTrackr inherits Lumina's "atelier" era so web + iOS share one language:
//   • Neutrals — warm void/ivory (dark) and warm paper/ink (light) surfaces,
//     text tiers, and borders, taken from Lumina's light/dark schemes.
//   • Brand accent — Lumina aura (teal) primary + spark (coral) secondary, on a
//     near-black onAccent. Used for interactive/brand moments (toggles, CTAs,
//     selection, branding).
//   • Functional safety palette — a small set Lumina doesn't define because it
//     isn't a safety product: `alert` (red) for SOS / danger / high-risk /
//     urgent severity, and `positive` (green) for safe/confirmed. This is
//     domain semantics, kept deliberately separate from the brand accent so the
//     emergency UI never reads as "brand teal".
//   • One token scale for spacing, radius, and type so screens stop drifting.
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
        // ── Neutrals — inherited from @xlumina/system (atelier era, light + dark
        // schemes). Warm void/ivory in dark; warm paper/ink in light. These are
        // the dominant brand signal shared with the Lumina web surface.
        static let background = SwiftUI.Color(light: 0xF3ECE1, dark: 0x06070A)
        static let surface = SwiftUI.Color(light: 0xFFFCF7, dark: 0x101217)
        /// Nested surface — inputs and tiles sit on a panel (Lumina surfaceRaised).
        static let surfaceHigh = SwiftUI.Color(lightHex: 0x15140F, lightAlpha: 0.05, darkHex: 0xFFFFFF, darkAlpha: 0.06)
        /// Hairline separators and panel strokes (Lumina border.subtle).
        static let hairline = SwiftUI.Color(lightHex: 0x15140F, lightAlpha: 0.10, darkHex: 0xFFFFFF, darkAlpha: 0.08)

        static let textPrimary = SwiftUI.Color(light: 0x15140F, dark: 0xF5EEE5)
        static let textSecondary = SwiftUI.Color(lightHex: 0x15140F, lightAlpha: 0.74, darkHex: 0xF5EEE5, darkAlpha: 0.72)
        static let textTertiary = SwiftUI.Color(lightHex: 0x15140F, lightAlpha: 0.50, darkHex: 0xF5EEE5, darkAlpha: 0.40)

        // ── Brand accent — Lumina "atelier" era: aura (teal) + spark (coral).
        // Deepened in light mode for legible contrast; same hue family in dark.
        static let accent = SwiftUI.Color(light: 0x0E9A88, dark: 0x73F2DF)
        static let accentSecondary = SwiftUI.Color(light: 0xD9542F, dark: 0xFF7D60)
        /// Foreground on top of an `accent` fill (Lumina onPrimary).
        static let onAccent = SwiftUI.Color(light: 0x071010, dark: 0x071010)

        // ── Functional safety palette — domain semantics Lumina doesn't define.
        /// Danger / SOS / high-risk / urgent severity. Always red, both schemes.
        static let alert = SwiftUI.Color(light: 0xC8102E, dark: 0xFF5A5F)
        /// Safe / confirmed / delivered.
        static let positive = SwiftUI.Color(light: 0x1E7A4D, dark: 0x4FBF87)
    }

    // MARK: Typography

    enum Font {
        // Families bundled from @xlumina/system: Cormorant Garamond (display
        // serif) + Manrope (body sans). Referenced by PostScript name; sizes use
        // `relativeTo:` so they still scale with Dynamic Type.
        static let displayName = "CormorantGaramond-SemiBold"
        static let bodyRegular = "Manrope-Regular"
        static let bodyMedium = "Manrope-Medium"
        static let bodySemibold = "Manrope-SemiBold"
        static let boldName = "Manrope-Bold"

        /// Editorial serif display — for large titles only (poor at small sizes).
        static func display(_ size: CGFloat, relativeTo style: SwiftUI.Font.TextStyle = .largeTitle) -> SwiftUI.Font {
            .custom(displayName, size: size, relativeTo: style)
        }

        static func screenTitle() -> SwiftUI.Font { display(34, relativeTo: .largeTitle) }
        // Non-display titles use Manrope (bold/semibold) so mid-size headers stay
        // legible; reserve the serif `display` for true hero titles.
        static func title() -> SwiftUI.Font { .custom(boldName, size: 22, relativeTo: .title2) }
        static func title3() -> SwiftUI.Font { .custom(bodySemibold, size: 20, relativeTo: .title3) }
        static func sectionTitle() -> SwiftUI.Font { .custom(bodySemibold, size: 15, relativeTo: .subheadline) }
        static func cardTitle() -> SwiftUI.Font { .custom(bodySemibold, size: 17, relativeTo: .headline) }
        static func body() -> SwiftUI.Font { .custom(bodyRegular, size: 15, relativeTo: .subheadline) }
        /// Emphasized body — use instead of `body().weight(.semibold)` so the real
        /// Manrope SemiBold cut is used rather than a synthesized weight.
        static func bodyStrong() -> SwiftUI.Font { .custom(bodySemibold, size: 15, relativeTo: .subheadline) }
        /// Bold body — real Manrope Bold cut (not synthesized).
        static func bodyBold() -> SwiftUI.Font { .custom(boldName, size: 15, relativeTo: .subheadline) }
        static func footnote() -> SwiftUI.Font { .custom(bodyRegular, size: 13, relativeTo: .footnote) }
        static func caption() -> SwiftUI.Font { .custom(bodyRegular, size: 12, relativeTo: .caption) }
        static func label() -> SwiftUI.Font { .custom(bodySemibold, size: 12, relativeTo: .caption) }
        static func caption2() -> SwiftUI.Font { .custom(bodyRegular, size: 11, relativeTo: .caption2) }
        static func caption2Strong() -> SwiftUI.Font { .custom(bodySemibold, size: 11, relativeTo: .caption2) }
    }
}

// MARK: - Global UIKit appearance (nav + tab bar fonts)

enum PulseAppearance {
    /// Route the UIKit chrome (navigation titles, tab-bar labels) through the
    /// bundled brand fonts so they match the SwiftUI surfaces. Call once at launch.
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        if let inline = UIFont(name: DS.Font.bodySemibold, size: 17) {
            nav.titleTextAttributes[.font] = inline
        }
        if let large = UIFont(name: DS.Font.displayName, size: 34) {
            nav.largeTitleTextAttributes[.font] = large
        }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        if let tabFont = UIFont(name: DS.Font.bodyMedium, size: 10) {
            let tab = UITabBarAppearance()
            tab.configureWithDefaultBackground()
            for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
                item.normal.titleTextAttributes[.font] = tabFont
                item.selected.titleTextAttributes[.font] = tabFont
            }
            UITabBar.appearance().standardAppearance = tab
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
    }
}

// MARK: - Adaptive color helper

extension Color {
    /// Build an adaptive color from two opaque hex values (light + dark).
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }

    /// Adaptive color with per-appearance alpha — for the translucent text and
    /// border tiers Lumina defines as rgba over the surface.
    init(lightHex: UInt, lightAlpha: Double, darkHex: UInt, darkAlpha: Double) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex, alpha: CGFloat(darkAlpha))
                : UIColor(hex: lightHex, alpha: CGFloat(lightAlpha))
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
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
    /// Label color over the fill. Defaults to Lumina onAccent (dark) for the
    /// light teal brand fill; pass `.white` for dark fills like `alert`.
    var foreground: Color = DS.Color.onAccent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.cardTitle())
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

/// Quiet secondary action — neutral surface, hairline border.
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.bodyStrong())
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
        case .urgent: DS.Color.alert
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
