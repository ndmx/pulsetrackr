import SwiftUI

struct IncidentDetailView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showsConcernDialog = false
    var incident: Incident

    private var liveIncident: Incident {
        incidentStore.incident(withID: incident.id) ?? incident
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                communityActions
                safetyActions
                if liveIncident.hasLocation {
                    directionsSection
                }
                detailCard
                updatesSection
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle(liveIncident.subtype.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Why are you reporting this?",
            isPresented: $showsConcernDialog,
            titleVisibility: .visible
        ) {
            ForEach(IncidentConcernReason.allCases) { reason in
                Button(reason.label) {
                    incidentStore.recordConcern(reason, for: liveIncident)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("PulseTrackr hides this report on your device and sends a private moderation signal for review.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: liveIncident.subtype.icon)
                    .font(.title2)
                    .foregroundStyle(liveIncident.category.color)
                    .frame(width: 56, height: 56)
                    .background(liveIncident.category.color.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(liveIncident.category.color.opacity(0.3), lineWidth: 1))

                DSSeverityBadge(severity: liveIncident.severity)

                Spacer()
            }

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Label(liveIncident.confidence.rawValue, systemImage: liveIncident.confidence.icon)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(liveIncident.confidence.color)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, 5)
                    .background(liveIncident.confidence.color.opacity(0.13), in: Capsule())

                Text(liveIncident.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(liveIncident.summary)
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(liveIncident.alertTone, systemImage: "bell.and.waves.left.and.right.fill")
                    .font(DS.Font.label())
                    .foregroundStyle(liveIncident.isHighRisk ? DS.Color.accent : DS.Color.textTertiary)
            }
        }
        .pulsePanel()
    }

    private var communityActions: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("What do you see?")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.md) {
                ForEach(CommunitySignal.allCases) { signal in
                    Button {
                        incidentStore.record(signal, for: liveIncident)
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: signal.icon)
                                .font(.subheadline)
                            Text(signal.label)
                                .font(DS.Font.body().weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(signal.color.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(signal.color.opacity(0.30), lineWidth: 1))
                        .foregroundStyle(signal.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .pulsePanel()
    }

    private var safetyActions: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Report concern")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)

            Text("Use this for false, abusive, private, or dangerous user-generated content. This hides the report on your device.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showsConcernDialog = true
            } label: {
                Label("Report or hide this", systemImage: "flag")
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
        .pulsePanel()
    }

    private var directionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Get directions")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)

            HStack(spacing: DS.Space.md) {
                Button {
                    openURL(liveIncident.googleMapsAreaURL)
                } label: {
                    Label("View area", systemImage: "map")
                }
                .buttonStyle(DSSecondaryButtonStyle())

                Button {
                    openURL(liveIncident.googleMapsDirectionsURL)
                } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .buttonStyle(DSSecondaryButtonStyle())
            }

            Text("Opens Google Maps to the approximate incident area. Your location is never included.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textTertiary)
        }
        .pulsePanel()
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: DS.Space.md) {
                    Image(systemName: row.icon)
                        .font(.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .frame(width: 20)

                    Text(row.label)
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)

                    Spacer()

                    Text(row.value)
                        .font(DS.Font.body().weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, DS.Space.md)

                if index < detailRows.count - 1 {
                    Divider().overlay(DS.Color.hairline)
                }
            }
        }
        .pulsePanel()
    }

    private var detailRows: [(label: String, value: String, icon: String)] {
        [
            ("Category", liveIncident.category.label, liveIncident.category.icon),
            ("Type", liveIncident.subtype.label, liveIncident.subtype.icon),
            ("Severity", liveIncident.severity.rawValue, "exclamationmark.triangle"),
            ("Status", liveIncident.status.rawValue, "dot.radiowaves.left.and.right"),
            ("Area", liveIncident.neighborhood, "mappin.and.ellipse"),
            ("Community signal", liveIncident.signalSummary, "person.2.fill"),
        ]
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Live updates")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)

            if liveIncident.updates.isEmpty {
                Text("No updates yet. Community signals will appear here as they come in.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(liveIncident.updates) { update in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(update.message)
                            .font(DS.Font.body())
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(update.timestamp, style: .relative)
                            .font(DS.Font.caption())
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Color.hairline, lineWidth: 1))
                }
            }
        }
        .pulsePanel()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        IncidentDetailView(incident: Incident.seedIncidents[0])
            .environmentObject(IncidentStore.preview)
    }
}
#endif
