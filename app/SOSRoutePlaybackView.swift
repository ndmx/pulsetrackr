import SwiftUI

struct SOSRoutePlaybackView: View {
    @EnvironmentObject private var sosStore: SOSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                summary
                timeline
                queueState
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("SOS route")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(Color.cyan.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent direction of travel")
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(directionText)
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DS.Space.md) {
                SOSRouteMetric(value: "\(sosStore.trail.count)", label: "points")
                SOSRouteMetric(value: sosStore.lastKnownPoint?.timestamp.formatted(date: .omitted, time: .shortened) ?? "—", label: "last seen")
                SOSRouteMetric(value: "\(sosStore.pendingRemoteEventCount)", label: "queued")
            }
        }
        .pulsePanel()
    }

    @ViewBuilder
    private var timeline: some View {
        if sosStore.trail.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSectionHeader(title: "Trail")
                Text("No SOS trail has been captured yet.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .pulsePanel()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSectionHeader(title: "Trail")

                ForEach(Array(sosStore.trail.suffix(12).enumerated()), id: \.element.id) { index, point in
                    SOSRoutePointRow(
                        point: point,
                        isNewest: index == Array(sosStore.trail.suffix(12)).count - 1
                    )
                }
            }
            .pulsePanel()
        }
    }

    private var queueState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Upload")

            HStack(spacing: DS.Space.md) {
                Image(systemName: uploadIcon)
                    .foregroundStyle(uploadColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(sosStore.uploadStatusText)
                        .font(DS.Font.bodyBold())
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Failed updates stay in the local queue until retry succeeds.")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            if sosStore.failedRemoteEventCount > 0 || sosStore.deliveryState == .failed {
                Button {
                    sosStore.retryQueuedEvents()
                } label: {
                    Label("Retry now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DSPrimaryButtonStyle(tint: IncidentSeverity.high.tint, foreground: .white))
            }
        }
        .pulsePanel()
    }

    private var directionText: String {
        guard let direction = sosStore.latestDirectionOfTravel else {
            return "Direction appears once two trail points are captured."
        }

        let bearing = Int(direction.bearingDegrees.rounded())
        if let speed = direction.speedMetersPerSecond {
            return "\(bearing) degrees, about \(String(format: "%.1f", speed)) m/s"
        }
        return "\(bearing) degrees from the latest trail"
    }

    private var uploadIcon: String {
        switch sosStore.deliveryState {
        case .delivered: "checkmark.icloud.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.icloud.fill"
        case .localOnly: "iphone"
        case .ready: "bell.fill"
        }
    }

    private var uploadColor: Color {
        switch sosStore.deliveryState {
        case .delivered: DS.Color.positive
        case .syncing: IncidentSeverity.medium.tint
        case .failed: IncidentSeverity.high.tint
        case .localOnly: .cyan
        case .ready: DS.Color.textSecondary
        }
    }
}

private struct SOSRoutePointRow: View {
    var point: SOSTrailPoint
    var isNewest: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                Circle()
                    .fill(isNewest ? DS.Color.accent.opacity(0.20) : Color.cyan.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: point.course == nil ? "location.fill" : "location.north.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(isNewest ? DS.Color.accent : .cyan)
                    .rotationEffect(.degrees(point.course ?? 0))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isNewest ? "Last known position" : "Trail point")
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
}

private struct SOSRouteMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(DS.Font.caption2Strong())
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        SOSRoutePlaybackView()
            .environmentObject(SOSStore())
    }
}
