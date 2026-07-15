import CoreLocation
import SwiftUI

/// Walker flow for a "Walk with me" escort session: pick one accepted app
/// trusted contact, share live trail, then mark arrived or stop sharing.
struct EscortView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRelationship: SOSAppTrustedContactRelationship?
    @State private var isShowingTrustedContacts = false
    @State private var didConfirmArrival = false
    @State private var isLoadingContacts = false
    @State private var loadError: String?

    private var acceptedOutgoingContacts: [SOSAppTrustedContactRelationship] {
        (sosStore.appTrustedContactList?.outgoing ?? [])
            .filter { $0.status == "accepted" }
    }

    private var isEscortActive: Bool {
        sosStore.isActive && sosStore.session?.kind == .escort
    }

    var body: some View {
        NavigationStack {
            Group {
                if didConfirmArrival {
                    arrivalConfirmation
                } else if isEscortActive {
                    activeSession
                } else {
                    contactPicker
                }
            }
            .background(DS.Color.background)
            .navigationTitle("Walk with me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEscortActive ? "Close" : "Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingTrustedContacts) {
                NavigationStack {
                    SOSTrustedContactsView()
                        .environmentObject(sosStore)
                }
            }
            .task {
                await refreshContacts()
            }
        }
    }

    // MARK: - Step 1: contact picker

    private var contactPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                headerCard

                if isLoadingContacts {
                    ProgressView("Loading contacts…")
                        .frame(maxWidth: .infinity)
                        .padding(DS.Space.xl)
                } else if acceptedOutgoingContacts.isEmpty {
                    emptyContactsCard
                } else {
                    contactsList
                }

                if let loadError {
                    Text(loadError)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "figure.walk")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 46, height: 46)
                .background(DS.Color.accent.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Share a calm walk")
                    .font(DS.Font.cardTitle())
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Choose exactly one in-app trusted contact. They’ll see your live location until you arrive or stop sharing — no emergency framing.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pulsePanel()
    }

    private var emptyContactsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "In-app contacts")

            Text("You need an accepted in-app trusted contact before you can walk with someone. Invite them from SOS contacts, then come back here.")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingTrustedContacts = true
            } label: {
                Label("Open SOS contacts", systemImage: "person.badge.plus")
            }
            .buttonStyle(DSPrimaryButtonStyle(tint: DS.Color.accent))
        }
        .pulsePanel()
    }

    private var contactsList: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Share with")

            ForEach(acceptedOutgoingContacts) { relationship in
                Button {
                    selectedRelationship = relationship
                    startEscort(with: relationship)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DS.Color.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(relationship.trustedContactDisplayName)
                                .font(DS.Font.bodyBold())
                                .foregroundStyle(DS.Color.textPrimary)
                            Text("In-app trusted contact")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Color.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(DS.Space.md)
                    .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .pulsePanel()
    }

    // MARK: - Step 2: active walk

    private var activeSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                statusCard
                actions
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sharing your walk")
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(recipientName)
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            if let startedAt = sosStore.session?.startedAt {
                HStack(spacing: DS.Space.sm) {
                    Text("Elapsed")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(DS.Font.bodyBold())
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: DS.Space.md) {
                escortMetric(
                    value: "\(sosStore.trail.count)",
                    label: "trail points"
                )
                escortMetric(
                    value: escortUploadLabel,
                    label: "upload"
                )
            }

            Text("Sharing your live location with \(recipientName). This is not an emergency alert.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastRemoteError = sosStore.lastRemoteError {
                Text(lastRemoteError)
                    .font(DS.Font.caption2())
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pulsePanel()
    }

    private var actions: some View {
        VStack(spacing: DS.Space.md) {
            Button {
                sosStore.markArrivedSafely()
                withAnimation(.snappy) {
                    didConfirmArrival = true
                }
            } label: {
                Label("I've arrived", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(DSPrimaryButtonStyle(tint: DS.Color.positive, foreground: .white))

            Button {
                sosStore.stopSession()
                dismiss()
            } label: {
                Text("Stop sharing")
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
    }

    // MARK: - Arrival confirmation

    private var arrivalConfirmation: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(DS.Color.positive)

            VStack(spacing: DS.Space.sm) {
                Text("You arrived safely")
                    .font(DS.Font.title())
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Live location sharing has ended. \(recipientName) can see that you arrived.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.lg)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(DSPrimaryButtonStyle(tint: DS.Color.accent))
            .padding(.horizontal, DS.Space.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.lg)
    }

    // MARK: - Helpers

    private var recipientName: String {
        if let selected = selectedRelationship {
            return selected.trustedContactDisplayName
        }
        if let relationshipId = sosStore.session?.escortRelationshipId,
           let match = acceptedOutgoingContacts.first(where: { $0.id == relationshipId }) {
            return match.trustedContactDisplayName
        }
        return "your contact"
    }

    private var escortUploadLabel: String {
        switch sosStore.deliveryState {
        case .localOnly: return "On device"
        case .ready: return "Ready"
        case .syncing: return "Sending"
        case .delivered: return "Shared"
        case .failed: return "Retrying"
        }
    }

    private func escortMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(DS.Font.caption2Strong())
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func startEscort(with relationship: SOSAppTrustedContactRelationship) {
        sosStore.startSession(
            from: locationManager.currentLocation,
            kind: .escort,
            escortRelationship: relationship
        )
    }

    private func refreshContacts() async {
        isLoadingContacts = true
        loadError = nil
        defer { isLoadingContacts = false }
        do {
            try await sosStore.refreshAppTrustedContacts()
        } catch {
            // Offline / unconfigured Firebase is fine if a cached list exists.
            if acceptedOutgoingContacts.isEmpty {
                loadError = "Couldn’t refresh in-app contacts. Check your connection and try again."
            }
        }
    }
}

#Preview {
    EscortView()
        .environmentObject(SOSStore())
        .environmentObject(LocationManager())
}
