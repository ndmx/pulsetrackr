import SwiftUI
import UIKit

/// Branded Open Graph–style share card for an incident.
/// Built at 600×315 pt and rendered at scale 2 → 1200×630 px for link-preview cropping.
struct IncidentShareCard: View {
    let incident: Incident

    private static let cardWidth: CGFloat = 600
    private static let cardHeight: CGFloat = 315
    private static let renderScale: CGFloat = 2

    /// Near-black map aesthetic (fixed dark; not adaptive).
    private static let cardBackground = Color(red: 6 / 255, green: 7 / 255, blue: 10 / 255)
    private static let cardBorder = Color.white.opacity(0.10)
    private static let textPrimary = Color(red: 0xF5 / 255, green: 0xEE / 255, blue: 0xE5 / 255)
    private static let textSecondary = Color(red: 0xF5 / 255, green: 0xEE / 255, blue: 0xE5 / 255).opacity(0.72)
    private static let textTertiary = Color(red: 0xF5 / 255, green: 0xEE / 255, blue: 0xE5 / 255).opacity(0.40)

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: incident.reportedAt, relativeTo: Date())
    }

    private var shareHostAndPath: String {
        guard let url = ShareConfig.shareURL(for: incident) else {
            return ShareConfig.shareBaseURL.host ?? "pulsetrackr.example"
        }
        let host = url.host ?? ""
        let path = url.path
        if host.isEmpty { return path }
        return host + path
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.cardBackground

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    categoryRow
                    Spacer(minLength: 12)
                    Text("PulseTrackr")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.textTertiary)
                }

                Spacer(minLength: 16)

                Text(incident.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Self.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 10)

                Text("\(incident.neighborhood) · \(relativeTime)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.textSecondary)
                    .lineLimit(1)

                Spacer().frame(height: 14)

                HStack(spacing: 10) {
                    DSSeverityBadge(severity: incident.severity)
                    Text(incident.confidenceLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(incident.confidence.color)
                        .lineLimit(1)
                }

                Spacer().frame(height: 8)

                Text(incident.alertTone)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(incident.isHighRisk ? DS.Color.alert : Self.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("See live updates on PulseTrackr")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Self.textSecondary)
                    Text(shareHostAndPath)
                        .font(.system(size: 11, weight: .regular).monospaced())
                        .foregroundStyle(Self.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(28)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Self.cardBorder, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var categoryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: incident.category.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(incident.category.color)
                .frame(width: 36, height: 36)
                .background(incident.category.color.opacity(0.18), in: Circle())
                .overlay(Circle().stroke(incident.category.color.opacity(0.35), lineWidth: 1))

            Text(incident.category.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.textSecondary)
                .lineLimit(1)
        }
    }

    /// Renders the card to a 1200×630 px bitmap (600×315 @ scale 2).
    @MainActor
    static func render(incident: Incident) -> UIImage? {
        let view = IncidentShareCard(incident: incident)
        let renderer = ImageRenderer(content: view)
        renderer.scale = renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
