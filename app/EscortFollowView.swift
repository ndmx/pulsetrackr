import CoreLocation
import SwiftUI

/// Accumulates successive escort alert location updates into an ordered trail.
/// Alert documents only carry `lastKnownLocation`; the recipient builds the path client-side.
@MainActor
final class EscortFollowTrailStore: ObservableObject {
    @Published private(set) var trail: [SOSTrailPoint] = []
    @Published private(set) var ownerDisplayName: String = ""
    @Published private(set) var status: String = "active"
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var sessionID: String?
    @Published private(set) var isArrivedSafely: Bool = false

    private let coordinateEpsilon = 0.00001

    func apply(alert: SOSAppAlert) {
        guard alert.kind == .escort else { return }

        if let sessionID, sessionID != alert.sessionID {
            // New escort session — reset accumulated trail.
            trail = []
            isArrivedSafely = false
        }

        sessionID = alert.sessionID
        ownerDisplayName = alert.ownerDisplayName
        status = alert.status
        lastUpdatedAt = alert.updatedAt

        if alert.status != "active" {
            // Terminal: arrived safely when resolved (backend uses status "resolved").
            isArrivedSafely = true
        }

        if let location = alert.lastKnownLocation {
            appendIfUnique(
                SOSTrailPoint(
                    coordinate: location.coordinate,
                    timestamp: location.capturedAt
                )
            )
        }
    }

    func apply(alerts: [SOSAppAlert], preferredSessionID: String? = nil) {
        let escortAlerts = alerts
            .filter { $0.kind == .escort }
            .sorted { $0.updatedAt < $1.updatedAt }

        let focused: [SOSAppAlert]
        if let preferredSessionID {
            focused = escortAlerts.filter { $0.sessionID == preferredSessionID }
        } else if let latest = escortAlerts.last {
            focused = escortAlerts.filter { $0.sessionID == latest.sessionID }
        } else {
            focused = []
        }

        for alert in focused {
            apply(alert: alert)
        }
    }

    private func appendIfUnique(_ point: SOSTrailPoint) {
        if let last = trail.last {
            let sameTime = abs(last.timestamp.timeIntervalSince(point.timestamp)) < 0.5
            let sameCoordinate =
                abs(last.coordinate.latitude - point.coordinate.latitude) < coordinateEpsilon &&
                abs(last.coordinate.longitude - point.coordinate.longitude) < coordinateEpsilon
            if sameTime && sameCoordinate {
                return
            }
            // Keep chronological order; ignore out-of-order older points.
            if point.timestamp < last.timestamp {
                return
            }
        }
        trail.append(point)
    }
}

/// Recipient view for an active or resolved escort walk.
struct EscortFollowView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @StateObject private var trailStore = EscortFollowTrailStore()

    var initialAlert: SOSAppAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                if trailStore.isArrivedSafely {
                    arrivedBanner
                }
                trailSection
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("Shared walk")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ingestAlerts()
        }
        .onChange(of: sosStore.appAlerts) { _, _ in
            ingestAlerts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 46, height: 46)
                    .background(DS.Color.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(displayName) is sharing a walk with you")
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(statusText)
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            HStack(spacing: DS.Space.md) {
                followMetric(value: "\(trailStore.trail.count)", label: "points")
                followMetric(value: lastUpdatedLabel, label: "updated")
                followMetric(value: trailStore.isArrivedSafely ? "Arrived" : "Live", label: "status")
            }
        }
        .pulsePanel()
    }

    private var arrivedBanner: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(DS.Color.positive)
            VStack(alignment: .leading, spacing: 4) {
                Text("Arrived safely")
                    .font(DS.Font.bodyBold())
                    .foregroundStyle(DS.Color.positive)
                Text("\(displayName) marked their walk complete. Location sharing has ended.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.positive.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var trailSection: some View {
        if trailStore.trail.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSectionHeader(title: "Walk trail")
                Text("Waiting for the first location update from \(displayName).")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .pulsePanel()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSectionHeader(title: "Walk trail")

                ForEach(Array(trailStore.trail.suffix(16).enumerated()), id: \.element.id) { index, point in
                    let visible = Array(trailStore.trail.suffix(16))
                    escortTrailRow(point: point, isNewest: index == visible.count - 1)
                }
            }
            .pulsePanel()
        }
    }

    private func escortTrailRow(point: SOSTrailPoint, isNewest: Bool) -> some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                Circle()
                    .fill(isNewest ? DS.Color.accent.opacity(0.20) : DS.Color.accent.opacity(0.10))
                    .frame(width: 38, height: 38)
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(isNewest ? DS.Color.accent : DS.Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isNewest ? "Latest position" : "Trail point")
                    .font(DS.Font.bodyBold())
                    .foregroundStyle(DS.Color.textPrimary)
                Text("\(point.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(point.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(point.timestamp, style: .time)
                .font(DS.Font.label())
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func followMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(DS.Font.caption2Strong())
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var displayName: String {
        let name = trailStore.ownerDisplayName
        return name.isEmpty ? (initialAlert?.ownerDisplayName ?? "Someone") : name
    }

    private var statusText: String {
        if trailStore.isArrivedSafely {
            return "Walk finished — arrived safely."
        }
        if trailStore.status == "active" {
            return "Live walk in progress."
        }
        return "Walk status: \(trailStore.status)."
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt = trailStore.lastUpdatedAt else { return "—" }
        return lastUpdatedAt.formatted(date: .omitted, time: .shortened)
    }

    private func ingestAlerts() {
        if let initialAlert {
            trailStore.apply(alerts: sosStore.appAlerts, preferredSessionID: initialAlert.sessionID)
            // Ensure the seed alert is applied even if not yet in the store list.
            if trailStore.trail.isEmpty || trailStore.sessionID != initialAlert.sessionID {
                trailStore.apply(alert: initialAlert)
            }
        } else {
            trailStore.apply(alerts: sosStore.appAlerts)
        }
    }
}

#Preview {
    NavigationStack {
        EscortFollowView(
            initialAlert: SOSAppAlert(
                id: "preview",
                sessionID: "s1",
                ownerUID: "u1",
                ownerDisplayName: "Ada",
                status: "active",
                lastKnownLocation: SOSLocationSnapshot(latitude: 6.52, longitude: 3.37),
                updatedAt: .now,
                kind: .escort
            )
        )
        .environmentObject(SOSStore())
    }
}
