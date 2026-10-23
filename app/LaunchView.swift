import SwiftUI

// Lumina Design System · Variation 04 · Created by ndmx
// Map Safety Glass keeps onboarding quiet and reserves strong status colors for safety.
struct LaunchView: View {
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(DS.Color.accent)
                    Text("Pulsetrackr")
                        .font(DS.Font.display(32, relativeTo: .largeTitle))
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .padding(.bottom, 72)

                Text("Know what's happening nearby.")
                    .font(DS.Font.display(46, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("See local reports before you head out, and share what you observe.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, 44)

                VStack(spacing: 0) {
                    FeatureRow(
                        icon: "map",
                        color: DS.Color.accent,
                        title: "Explore nearby reports",
                        description: "See incidents in your watch area."
                    )
                    Divider().overlay(DS.Color.hairline).padding(.vertical, DS.Space.lg)
                    FeatureRow(
                        icon: "plus.circle",
                        color: DS.Color.accent,
                        title: "Report what you see",
                        description: "Add a description, photo, or voice note."
                    )
                    Divider().overlay(DS.Color.hairline).padding(.vertical, DS.Space.lg)
                    FeatureRow(
                        icon: "location.slash",
                        color: DS.Color.positive,
                        title: "Keep your location private",
                        description: "Public reports show an approximate area."
                    )
                }

                Button("Open the map", action: onContinue)
                    .buttonStyle(DSPrimaryButtonStyle())
                    .padding(.top, 52)

                Text("For immediate danger, contact local emergency services.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.top, DS.Space.md)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.background)
    }
}

private struct FeatureRow: View {
    var icon: String
    var color: Color
    var title: String
    var description: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(DS.Font.bodyStrong())
                    .foregroundStyle(DS.Color.textPrimary)
                Text(description)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    LaunchView { }
}
