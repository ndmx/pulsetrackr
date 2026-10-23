import SwiftUI
import UIKit

struct SOSTrustedContactsView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @AppStorage(AppStorageKey.sosOwnerDisplayName) private var ownerName = ""
    @State private var inviteCode = ""
    @State private var inviteExpiresAt: Date?
    @State private var acceptanceCode = ""
    @State private var recipientName = ""
    @State private var isCreating = false
    @State private var isAccepting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                acceptedContacts
                createInvite
                acceptInvite
                reliabilityNote
                legacyContacts
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("SOS contacts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sosStore.loadTrustedContacts()
            try? await sosStore.refreshAppTrustedContacts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("Keep SOS in PulseTrackr", systemImage: "app.badge.fill")
                .font(DS.Font.cardTitle())
                .foregroundStyle(DS.Color.textPrimary)
            Text("Only people who accept your invite in PulseTrackr receive your SOS and live location. Invite someone you trust before relying on alerts.")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)
        }
        .pulsePanel()
    }

    private var acceptedContacts: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Accepted in-app contacts")
            if let list = sosStore.appTrustedContactList {
                HStack(spacing: DS.Space.md) {
                    SOSMiniMetric(value: "\(list.outgoing.count)", label: "you alert")
                    SOSMiniMetric(value: "\(list.incoming.count)", label: "alert you")
                }
                if list.outgoing.isEmpty {
                    Text("No one can receive your SOS yet. Create an invite below and ask them to accept it in the app.")
                        .font(DS.Font.caption())
                        .foregroundStyle(IncidentSeverity.high.tint)
                }
                ForEach(list.outgoing) { relationship in
                    HStack {
                        Label(relationship.trustedContactDisplayName, systemImage: "checkmark.shield.fill")
                            .font(DS.Font.bodyStrong())
                            .foregroundStyle(DS.Color.textPrimary)
                        Spacer()
                        Button("Remove", role: .destructive) { revoke(relationship) }
                            .font(DS.Font.caption())
                    }
                }
            } else {
                Text("Loading your PulseTrackr contacts…")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .pulsePanel()
    }

    private var createInvite: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Invite a recipient")
            Text("Share the one-time code with someone who has PulseTrackr. Their acceptance lets your SOS alert them; it does not alert you about their SOS.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
            SOSTextField(title: "Your name they'll see", text: $ownerName, icon: "person.text.rectangle.fill")
            Button {
                createAppInvite()
            } label: {
                Label(isCreating ? "Creating code…" : "Create invite code", systemImage: "qrcode")
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isCreating)
            if !inviteCode.isEmpty {
                HStack {
                    VStack(alignment: .leading) {
                        Text(inviteCode)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                        if let inviteExpiresAt {
                            Text("Expires \(inviteExpiresAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(DS.Font.caption())
                        }
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = inviteCode
                        statusMessage = "Invite code copied."
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .accessibilityLabel("Copy invite code")
                }
                .padding(DS.Space.md)
                .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
        }
        .pulsePanel()
    }

    private var acceptInvite: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Accept an invite")
            Text("A person you trust can give you their code so you receive their SOS in PulseTrackr.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
            SOSTextField(title: "Invite code", text: $acceptanceCode, icon: "number")
            SOSTextField(title: "Name they'll see", text: $recipientName, icon: "person.fill.checkmark")
            Button {
                acceptAppInvite()
            } label: {
                Label(isAccepting ? "Accepting…" : "Accept invite", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(DSSecondaryButtonStyle())
            .disabled(isAccepting || acceptanceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let statusMessage {
                Text(statusMessage).font(DS.Font.caption()).foregroundStyle(DS.Color.positive)
            }
            if let errorMessage {
                Text(errorMessage).font(DS.Font.caption()).foregroundStyle(IncidentSeverity.high.tint)
            }
        }
        .pulsePanel()
    }

    private var reliabilityNote: some View {
        Text("SOS needs location and internet access. Recipients must have PulseTrackr installed. Device notifications require their permission; the alert remains visible in the app if a push cannot arrive. PulseTrackr does not dispatch emergency services.")
            .font(DS.Font.caption())
            .foregroundStyle(DS.Color.textSecondary)
            .pulsePanel()
    }

    @ViewBuilder
    private var legacyContacts: some View {
        if !sosStore.trustedContacts.isEmpty {
            DisclosureGroup("Previous phone and email contacts") {
                Text("These contacts stay on your device but no longer receive SOS messages. Invite them to PulseTrackr to restore alerts.")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                ForEach(sosStore.trustedContacts) { contact in
                    HStack {
                        Text(contact.displayName)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            sosStore.deleteTrustedContact(withID: contact.id)
                        }
                    }
                }
            }
            .font(DS.Font.bodyStrong())
            .pulsePanel()
        }
    }

    private func createAppInvite() {
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                let invite = try await sosStore.createAppTrustedContactInvite(ownerDisplayName: ownerName)
                inviteCode = invite.inviteCode
                inviteExpiresAt = invite.expiresAt
                statusMessage = "Share this code only with the person you trust."
            } catch {
                errorMessage = "Could not create an invite. Check your connection and try again."
            }
        }
    }

    private func acceptAppInvite() {
        isAccepting = true
        errorMessage = nil
        Task {
            defer { isAccepting = false }
            do {
                let relationship = try await sosStore.acceptAppTrustedContactInvite(
                    inviteCode: acceptanceCode,
                    trustedContactDisplayName: recipientName
                )
                acceptanceCode = ""
                statusMessage = "Accepted. \(relationship.ownerDisplayName)'s SOS can now alert you in PulseTrackr."
            } catch {
                errorMessage = "Could not accept the invite. Check that the code is correct, unused, and unexpired."
            }
        }
    }

    private func revoke(_ relationship: SOSAppTrustedContactRelationship) {
        Task {
            do {
                try await sosStore.revokeAppTrustedContact(relationship)
            } catch {
                errorMessage = "Could not remove this contact. Try again."
            }
        }
    }
}

private struct SOSTextField: View {
    var title: String
    @Binding var text: String
    var icon: String

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 22)
            TextField(title, text: $text)
                .textInputAutocapitalization(title == "Invite code" ? .never : .words)
                .autocorrectionDisabled()
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

private struct SOSMiniMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(DS.Color.textPrimary)
            Text(label)
                .font(DS.Font.caption2Strong())
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

#Preview {
    NavigationStack {
        SOSTrustedContactsView()
            .environmentObject(SOSStore())
    }
}
