import SwiftUI

struct IncidentDangerHalo: View {
    var incident: Incident

    var body: some View {
        ZStack {
            Circle()
                .fill(incident.category.color.opacity(fillOpacity))
                .frame(width: outerDiameter, height: outerDiameter)
                .blur(radius: blurRadius)

            Circle()
                .stroke(incident.category.color.opacity(0.30), lineWidth: 1.5)
                .frame(width: outerDiameter * 0.72, height: outerDiameter * 0.72)

            if incident.isHighRisk {
                Circle()
                    .stroke(incident.category.color.opacity(0.18), lineWidth: 1)
                    .frame(width: outerDiameter, height: outerDiameter)
            }
        }
        .allowsHitTesting(false)
    }

    private var outerDiameter: CGFloat {
        switch incident.severity {
        case .urgent: 154
        case .high: 124
        case .medium: 94
        case .low: 76
        }
    }

    private var fillOpacity: Double {
        incident.isHighRisk ? 0.25 : 0.17
    }

    private var blurRadius: CGFloat {
        incident.isHighRisk ? 5 : 3
    }
}

struct SOSTrailBreadcrumb: View {
    var artifact: SOSMapTrailArtifact

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.18 * artifact.prominence))
                .frame(width: artifact.isNewest ? 42 : 30, height: artifact.isNewest ? 42 : 30)

            if let course = artifact.point.course {
                Image(systemName: "location.north.fill")
                    .font(.system(size: artifact.isNewest ? 16 : 12, weight: .heavy))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.degrees(course))
                    .frame(width: artifact.isNewest ? 28 : 22, height: artifact.isNewest ? 28 : 22)
                    .background(.black.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(.cyan.opacity(0.60), lineWidth: 1))
            } else {
                Circle()
                    .fill(Color.cyan.opacity(0.38 + 0.42 * artifact.prominence))
                    .frame(width: artifact.isNewest ? 13 : 8, height: artifact.isNewest ? 13 : 8)
                    .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: artifact.isNewest ? 1.5 : 1))
            }
        }
        .opacity(artifact.prominence)
        .accessibilityLabel(artifact.isNewest ? "Latest trail point" : "Recent trail point")
    }
}

struct SOSLastKnownMarker: View {
    var isActive: Bool
    var accuracy: Double?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill((isActive ? Color.red : Color.cyan).opacity(0.20))
                    .frame(width: 64, height: 64)
                    .blur(radius: 2)

                Image(systemName: isActive ? "sos.circle.fill" : "location.fill")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(isActive ? .red : .cyan)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.82), in: Circle())
                    .overlay(Circle().stroke(isActive ? .red : .cyan, lineWidth: 2))
            }

            if let accuracy {
                Text("±\(Int(accuracy.rounded()))m")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
            }
        }
        .accessibilityLabel(isActive ? "Active SOS location" : "Last known location")
    }
}
