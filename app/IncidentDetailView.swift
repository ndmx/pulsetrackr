import SwiftUI

struct IncidentDetailView: View {
    @EnvironmentObject private var incidentStore: IncidentStore
    @Environment(\.openURL) private var openURL
    var incident: Incident

    private var liveIncident: Incident {
        incidentStore.incident(withID: incident.id) ?? incident
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                communityActions
                if liveIncident.hasLocation {
                    directionsSection
                }
                detailCard
                updatesSection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(.black)
        .navigationTitle(liveIncident.subtype.label)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: liveIncident.subtype.icon)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(liveIncident.category.color, in: Circle())
                .shadow(color: liveIncident.category.color.opacity(0.55), radius: 14)

            VStack(alignment: .leading, spacing: 10) {
                Label(liveIncident.confidence.rawValue, systemImage: liveIncident.confidence.icon)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .textCase(.uppercase)
                    .foregroundStyle(liveIncident.confidence.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(liveIncident.confidence.color.opacity(0.13), in: Capsule())

                Text(liveIncident.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(liveIncident.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)

                Label(liveIncident.alertTone, systemImage: "bell.and.waves.left.and.right.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(liveIncident.isHighRisk ? .red : .white.opacity(0.52))
            }
        }
        .cardPanel()
    }

    private var communityActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you see?")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CommunitySignal.allCases) { signal in
                    Button {
                        incidentStore.record(signal, for: liveIncident)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: signal.icon)
                                .font(.subheadline)
                            Text(signal.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(signal.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(signal.color.opacity(0.30), lineWidth: 1))
                        .foregroundStyle(signal.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardPanel()
    }

    private var directionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Get directions")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                Button {
                    openURL(liveIncident.googleMapsAreaURL)
                } label: {
                    Label("View area", systemImage: "map.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08), lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    openURL(liveIncident.googleMapsDirectionsURL)
                } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.blue.opacity(0.34), lineWidth: 1))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            Text("Opens Google Maps to the approximate incident area. Your location is never included.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.40))
        }
        .cardPanel()
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: 20)

                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.54))

                    Spacer()

                    Text(row.value)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 11)

                if index < detailRows.count - 1 {
                    Divider().background(.white.opacity(0.07))
                }
            }
        }
        .cardPanel()
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Live updates")
                .font(.headline)
                .foregroundStyle(.white)

            if liveIncident.updates.isEmpty {
                Text("No updates yet. Community signals will appear here as they come in.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.44))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(liveIncident.updates) { update in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(update.message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.86))
                        Text(update.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.06), lineWidth: 1))
                }
            }
        }
        .cardPanel()
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
