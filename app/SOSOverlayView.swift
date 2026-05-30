import SwiftUI

struct SOSOverlayView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @EnvironmentObject private var locationManager: LocationManager
    @State private var isHolding = false
    @State private var isShowingRoute = false
    @State private var pendingResolutionAction: SOSResolutionAction?

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if sosStore.isActive {
                activePanel
            } else {
                holdButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 74)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.snappy, value: sosStore.isActive)
        .sheet(isPresented: $isShowingRoute) {
            NavigationStack {
                SOSRoutePlaybackView()
                    .environmentObject(sosStore)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            pendingResolutionAction?.title ?? "End SOS?",
            isPresented: Binding(
                get: { pendingResolutionAction != nil },
                set: { if !$0 { pendingResolutionAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingResolutionAction
        ) { action in
            Button(action.buttonTitle, role: action.role) {
                withAnimation(.snappy) {
                    action.apply(to: sosStore)
                }
                pendingResolutionAction = nil
            }
            Button("Keep SOS active", role: .cancel) {
                pendingResolutionAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var holdButton: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack {
                Circle()
                    .fill(DS.Color.alert.opacity(isHolding ? 0.28 : 0.18))
                    .frame(width: isHolding ? 84 : 70, height: isHolding ? 84 : 70)

                Circle()
                    .trim(from: 0, to: isHolding ? 1 : 0.18)
                    .stroke(DS.Color.alert, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: "sos.circle.fill")
                        .font(.system(size: 26, weight: .heavy))
                    Text("SOS")
                        .font(DS.Font.caption2())
                        .fontWeight(.heavy)
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(.black.opacity(0.84), in: Circle())
                .overlay(Circle().stroke(DS.Color.alert.opacity(0.80), lineWidth: 2))
            }
            .contentShape(Circle())
            .gesture(activationGesture)
            .accessibilityLabel("Hold to start SOS")
            .accessibilityHint("Starts a local emergency sharing session for trusted contacts.")
            .accessibilityAddTraits(.isButton)

            Text(isHolding ? "Keep holding" : "Hold for SOS")
                .font(DS.Font.caption2())
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.black.opacity(0.54), in: Capsule())

            Text("Alerts trusted contacts only")
                .font(DS.Font.caption2())
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.black.opacity(0.54), in: Capsule())

            if sosStore.activeTrustedContacts.isEmpty {
                Text("No contacts set")
                    .font(DS.Font.caption2())
                    .fontWeight(.bold)
                    .foregroundStyle(IncidentSeverity.high.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.58), in: Capsule())
            }
        }
    }

    private var activePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "sos.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Color.alert)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SOS active")
                        .font(DS.Font.cardTitle())
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    Text("Trusted contacts are being notified.")
                        .font(DS.Font.caption())
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            Label("PulseTrackr does not automatically contact police, ambulance, or emergency services.", systemImage: "person.2.wave.2.fill")
                .font(DS.Font.caption2())
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                statusChip(
                    icon: "location.fill",
                    title: "\(sosStore.trail.count) trail points"
                )
                statusChip(
                    icon: "tray.and.arrow.up.fill",
                    title: queueTitle
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Label(sosStore.uploadStatusText, systemImage: deliveryIcon)
                    .font(DS.Font.caption())
                    .fontWeight(.bold)
                    .foregroundStyle(deliveryColor)

                if let lastRemoteError = sosStore.lastRemoteError {
                    Text(lastRemoteError)
                        .font(DS.Font.caption2())
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            contactStrip

            HStack(spacing: 8) {
                Button {
                    isShowingRoute = true
                } label: {
                    Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(DS.Font.caption())
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SOSActionButtonStyle(tint: .cyan))

                if sosStore.failedRemoteEventCount > 0 || sosStore.deliveryState == .failed {
                    Button {
                        sosStore.retryQueuedEvents()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(DS.Font.caption())
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SOSActionButtonStyle(tint: IncidentSeverity.medium.tint))
                }
            }

            HStack(spacing: 8) {
                Button {
                    pendingResolutionAction = .resolved
                } label: {
                    Label("Resolve", systemImage: "checkmark.shield.fill")
                        .font(DS.Font.caption())
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SOSActionButtonStyle(tint: .cyan))

                Button {
                    pendingResolutionAction = .falseAlarm
                } label: {
                    Label("False alarm", systemImage: "xmark")
                        .font(DS.Font.caption())
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SOSActionButtonStyle(tint: DS.Color.alert))
            }
        }
        .padding(14)
        .frame(width: 316, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DS.Color.alert.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
    }

    private var activationGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.05, maximumDistance: 34)
            .onChanged { _ in
                withAnimation(.easeInOut(duration: 1.05)) {
                    isHolding = true
                }
            }
            .onEnded { completed in
                withAnimation(.snappy) {
                    isHolding = false
                    if completed {
                        sosStore.startSession(from: locationManager.currentLocation)
                    }
                }
            }
    }

    @ViewBuilder
    private var contactStrip: some View {
        if sosStore.activeTrustedContacts.isEmpty {
            Label("No trusted contacts. Location is still saved locally.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(DS.Font.caption())
                .fontWeight(.semibold)
                .foregroundStyle(IncidentSeverity.high.tint)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Trusted group")
                    .font(DS.Font.caption2())
                    .fontWeight(.heavy)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.42))

                ForEach(sosStore.activeTrustedContacts.prefix(3)) { contact in
                    HStack(spacing: 8) {
                        Image(systemName: sosStore.alertedContactIDs.contains(contact.id) ? "bell.badge.fill" : "bell.fill")
                            .font(.caption)
                            .foregroundStyle(sosStore.alertedContactIDs.contains(contact.id) ? DS.Color.positive : .white.opacity(0.52))
                            .frame(width: 18)
                        Text(contact.displayName)
                            .font(DS.Font.caption())
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        Spacer()
                        Text(sosStore.alertedContactIDs.contains(contact.id) ? "alerted" : "ready")
                            .font(DS.Font.caption2())
                            .fontWeight(.bold)
                            .foregroundStyle(sosStore.alertedContactIDs.contains(contact.id) ? DS.Color.positive : .white.opacity(0.46))
                    }
                }

                if sosStore.activeTrustedContacts.count > 3 {
                    Text("+\(sosStore.activeTrustedContacts.count - 3) more")
                        .font(DS.Font.caption2())
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
        }
    }

    private var queueTitle: String {
        if sosStore.failedRemoteEventCount > 0 {
            return "\(sosStore.failedRemoteEventCount) retry"
        }
        return "\(sosStore.pendingRemoteEventCount) queued"
    }

    private var deliveryIcon: String {
        switch sosStore.deliveryState {
        case .delivered: "checkmark.icloud.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.icloud.fill"
        case .localOnly: "iphone"
        case .ready: "bell.fill"
        }
    }

    private var deliveryColor: Color {
        switch sosStore.deliveryState {
        case .delivered: DS.Color.positive
        case .syncing: IncidentSeverity.medium.tint
        case .failed: IncidentSeverity.high.tint
        case .localOnly: .cyan
        case .ready: .white.opacity(0.82)
        }
    }

    private func statusChip(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(DS.Font.caption2())
            .fontWeight(.bold)
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.09), in: Capsule())
    }
}

private enum SOSResolutionAction: Identifiable {
    case resolved
    case falseAlarm

    var id: String {
        switch self {
        case .resolved: "resolved"
        case .falseAlarm: "falseAlarm"
        }
    }

    var title: String {
        switch self {
        case .resolved: "Resolve SOS?"
        case .falseAlarm: "Mark false alarm?"
        }
    }

    var message: String {
        switch self {
        case .resolved:
            "This ends live location sharing and records that you resolved the SOS."
        case .falseAlarm:
            "This ends live location sharing and records the session as a false alarm."
        }
    }

    var buttonTitle: String {
        switch self {
        case .resolved: "Resolve SOS"
        case .falseAlarm: "End as False Alarm"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .resolved: nil
        case .falseAlarm: .destructive
        }
    }

    @MainActor func apply(to store: SOSStore) {
        switch self {
        case .resolved:
            store.stopSession()
        case .falseAlarm:
            store.cancelSession()
        }
    }
}

private struct SOSActionButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint == DS.Color.alert ? .white : .black)
            .padding(.vertical, 9)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 0.92), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
