import SwiftUI

struct SOSRoutePlaybackView: View {
    @EnvironmentObject private var sosStore: SOSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                timeline
                queueState
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(.black)
        .navigationTitle("SOS route")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(.cyan.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent direction of travel")
                        .font(.headline)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    Text(directionText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                SOSRouteMetric(value: "\(sosStore.trail.count)", label: "points")
                SOSRouteMetric(value: sosStore.lastKnownPoint?.timestamp.formatted(date: .omitted, time: .shortened) ?? "—", label: "last seen")
                SOSRouteMetric(value: "\(sosStore.pendingRemoteEventCount)", label: "queued")
            }
        }
        .cardPanel(backgroundOpacity: 0.08)
    }

    @ViewBuilder
    private var timeline: some View {
        if sosStore.trail.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Trail")
                Text("No SOS trail has been captured yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .cardPanel(backgroundOpacity: 0.07)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Trail")

                ForEach(Array(sosStore.trail.suffix(12).enumerated()), id: \.element.id) { index, point in
                    SOSRoutePointRow(
                        point: point,
                        isNewest: index == Array(sosStore.trail.suffix(12)).count - 1
                    )
                }
            }
            .cardPanel(backgroundOpacity: 0.07)
        }
    }

    private var queueState: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Upload")

            HStack(spacing: 10) {
                Image(systemName: uploadIcon)
                    .foregroundStyle(uploadColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(sosStore.uploadStatusText)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Failed updates stay in the local queue until retry succeeds.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            if sosStore.failedRemoteEventCount > 0 || sosStore.deliveryState == .failed {
                Button {
                    sosStore.retryQueuedEvents()
                } label: {
                    Label("Retry now", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SOSRouteButtonStyle())
            }
        }
        .cardPanel(backgroundOpacity: 0.07)
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
        case .delivered: .green
        case .syncing: .yellow
        case .failed: .orange
        case .localOnly: .cyan
        case .ready: .white.opacity(0.78)
        }
    }
}

private struct SOSRoutePointRow: View {
    var point: SOSTrailPoint
    var isNewest: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isNewest ? Color.red.opacity(0.20) : Color.cyan.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: point.course == nil ? "location.fill" : "location.north.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(isNewest ? .red : .cyan)
                    .rotationEffect(.degrees(point.course ?? 0))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isNewest ? "Last known position" : "Trail point")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("\(point.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(point.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer()

            Text(point.timestamp, style: .time)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.58))
        }
    }
}

private struct SOSRouteMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.heavy)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SOSRouteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.vertical, 11)
            .background(Color.yellow.opacity(configuration.isPressed ? 0.72 : 0.92), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    NavigationStack {
        SOSRoutePlaybackView()
            .environmentObject(SOSStore())
    }
}
