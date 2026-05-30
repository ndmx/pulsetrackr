import ContactsUI
import SwiftUI

struct SOSTrustedContactsView: View {
    @EnvironmentObject private var sosStore: SOSStore
    @State private var editingContact: SOSTrustedContact?
    @State private var importedContact: SOSTrustedContact?
    @State private var isAddingContact = false
    @State private var isPickingContact = false
    @State private var contactImportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                contactList
                privacyNote
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Color.background)
        .navigationTitle("SOS contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isPickingContact = true
                    } label: {
                        Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                    }

                    Button {
                        editingContact = nil
                        isAddingContact = true
                    } label: {
                        Label("Add manually", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.headline)
                }
                .accessibilityLabel("Add trusted contact")
            }
        }
        .sheet(isPresented: $isAddingContact) {
            NavigationStack {
                SOSTrustedContactEditorView(contact: nil, isNewContact: true)
                    .environmentObject(sosStore)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingContact) { contact in
            NavigationStack {
                SOSTrustedContactEditorView(contact: contact)
                    .environmentObject(sosStore)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $importedContact) { contact in
            NavigationStack {
                SOSTrustedContactEditorView(contact: contact, isNewContact: true)
                    .environmentObject(sosStore)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isPickingContact) {
            SOSContactPicker(
                onSelect: { draft in
                    importedContact = draft
                    contactImportError = nil
                },
                onIncompleteSelection: {
                    contactImportError = "That contact has no phone number or email address."
                }
            )
            .ignoresSafeArea()
        }
        .alert("Could not import contact", isPresented: Binding(
            get: { contactImportError != nil },
            set: { if !$0 { contactImportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(contactImportError ?? "")
        }
        .onAppear {
            sosStore.loadTrustedContacts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: "sos.circle.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 46, height: 46)
                    .background(DS.Color.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("People to alert first")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("When you activate SOS, PulseTrackr sends your last known location, recent direction of travel, and live updates to active contacts.")
                        .font(DS.Font.body())
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DS.Space.md) {
                SOSMiniMetric(value: "\(sosStore.activeTrustedContacts.count)", label: "ready")
                SOSMiniMetric(value: "\(sosStore.trustedContacts.count)", label: "saved")
                SOSMiniMetric(value: "\(sosStore.alertedContacts.count)", label: "alerted")
            }
        }
        .pulsePanel()
    }

    @ViewBuilder
    private var contactList: some View {
        if sosStore.trustedContacts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SettingsSectionHeader(title: "Trusted group")

                ForEach(sosStore.trustedContacts) { contact in
                    SOSTrustedContactRow(contact: contact) {
                        sosStore.toggleTrustedContact(contact)
                    } editAction: {
                        editingContact = contact
                    } deleteAction: {
                        sosStore.deleteTrustedContact(withID: contact.id)
                    }
                }
            }
            .pulsePanel()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Trusted group")

            HStack(spacing: DS.Space.md) {
                Image(systemName: "person.2.slash")
                    .font(.title3)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(DS.Color.surfaceHigh, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("No contacts yet")
                        .font(DS.Font.cardTitle())
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Add at least one person before travel so SOS has somewhere to send alerts.")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Button {
                isPickingContact = true
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(DSPrimaryButtonStyle())

            Button {
                editingContact = nil
                isAddingContact = true
            } label: {
                Label("Add manually", systemImage: "square.and.pencil")
            }
            .buttonStyle(DSSecondaryButtonStyle())
        }
        .pulsePanel()
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(DS.Color.positive)
                .frame(width: 26)

            Text("Contacts are stored in the device Keychain. Exact location is shared only after you activate SOS, and PulseTrackr does not automatically contact police, ambulance, or emergency services. SOS history is kept only as long as needed for safety review and cleanup.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.xs)
    }
}

private struct SOSTrustedContactRow: View {
    var contact: SOSTrustedContact
    var toggleAction: () -> Void
    var editAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(contact.initials)
                .font(DS.Font.label())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(contact.isDeliverable ? DS.Color.accent : DS.Color.textTertiary, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(contact.displayName)
                        .font(DS.Font.bodyBold())
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)

                    if contact.lastNotifiedAt != nil {
                        Image(systemName: "bell.badge.fill")
                            .font(.caption2)
                            .foregroundStyle(DS.Color.positive)
                    }
                }

                Text(contact.destinationSummary)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)

                Text(contact.channelSummary)
                    .font(DS.Font.caption2Strong())
                    .foregroundStyle(contact.isDeliverable ? DS.Color.positive : IncidentSeverity.high.tint)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { contact.isActive }, set: { _ in toggleAction() }))
                .labelsHidden()
                .tint(DS.Color.accent)

            Menu {
                Button("Edit", systemImage: "pencil", action: editAction)
                Button("Remove", systemImage: "trash", role: .destructive, action: deleteAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(contact.isDeliverable ? DS.Color.hairline : IncidentSeverity.high.tint.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct SOSTrustedContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sosStore: SOSStore
    let contact: SOSTrustedContact?
    let isNewContact: Bool

    @State private var displayName: String
    @State private var relationshipLabel: String
    @State private var phoneNumber: String
    @State private var emailAddress: String
    @State private var channels: Set<SOSTrustedContactChannel>
    @State private var isActive: Bool

    init(contact: SOSTrustedContact?, isNewContact: Bool = false) {
        self.contact = contact
        self.isNewContact = isNewContact
        _displayName = State(initialValue: contact?.displayName ?? "")
        _relationshipLabel = State(initialValue: contact?.relationshipLabel ?? "")
        _phoneNumber = State(initialValue: contact?.phoneNumber ?? "")
        _emailAddress = State(initialValue: contact?.emailAddress ?? "")
        _channels = State(initialValue: contact?.notificationChannels ?? [.sms])
        _isActive = State(initialValue: contact?.isActive ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                editorSection
                channelSection
                consentSection
            }
            .padding(DS.Space.lg)
            .padding(.bottom, DS.Space.lg)
        }
        .background(DS.Color.background)
        .navigationTitle(isNewContact ? "Add contact" : "Edit contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Contact")
            SOSTextField(title: "Name", text: $displayName, icon: "person.fill")
            SOSTextField(title: "Relationship", text: $relationshipLabel, icon: "heart.fill")
            SOSTextField(title: "Phone", text: $phoneNumber, icon: "phone.fill", keyboard: .phonePad)
            SOSTextField(title: "Email", text: $emailAddress, icon: "envelope.fill", keyboard: .emailAddress)

            Toggle(isOn: $isActive) {
                Label("Active during SOS", systemImage: "bell.fill")
                    .font(DS.Font.bodyStrong())
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .tint(DS.Color.accent)
        }
        .pulsePanel()
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSectionHeader(title: "Alert routes")

            ForEach(SOSTrustedContactChannel.allCases, id: \.self) { channel in
                Toggle(isOn: channelBinding(channel)) {
                    Label(channel.label, systemImage: channel.iconName)
                        .font(DS.Font.bodyStrong())
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .tint(DS.Color.accent)
            }
        }
        .pulsePanel()
    }

    private var consentSection: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(DS.Color.positive)
            Text("Use contacts who know they may receive SOS location alerts from you. They should understand PulseTrackr alerts them directly and does not dispatch emergency services.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.xs)
    }

    private var canSave: Bool {
        let hasName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasDestination = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasName && hasDestination && channels.isEmpty == false
    }

    private func channelBinding(_ channel: SOSTrustedContactChannel) -> Binding<Bool> {
        Binding {
            channels.contains(channel)
        } set: { isEnabled in
            if isEnabled {
                channels.insert(channel)
            } else {
                channels.remove(channel)
            }
        }
    }

    private func save() {
        let updated = SOSTrustedContact(
            id: contact?.id ?? UUID(),
            displayName: displayName,
            relationshipLabel: relationshipLabel,
            phoneNumber: phoneNumber,
            emailAddress: emailAddress,
            notificationChannels: channels,
            consentedAt: contact?.consentedAt ?? Date(),
            lastNotifiedAt: contact?.lastNotifiedAt,
            isActive: isActive,
            createdAt: contact?.createdAt ?? Date()
        )
        sosStore.saveTrustedContact(updated)
        dismiss()
    }
}

private struct SOSTextField: View {
    var title: String
    @Binding var text: String
    var icon: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 22)
            TextField(title, text: $text)
                .textInputAutocapitalization(title == "Email" ? .never : .words)
                .keyboardType(keyboard)
                .autocorrectionDisabled(title == "Email" || title == "Phone")
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(DS.Space.md)
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.hairline, lineWidth: 1)
        )
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
        .background(DS.Color.surfaceHigh, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

private struct SOSContactPicker: UIViewControllerRepresentable {
    var onSelect: (SOSTrustedContact) -> Void
    var onIncompleteSelection: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onIncompleteSelection: onIncompleteSelection)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onSelect: (SOSTrustedContact) -> Void
        private let onIncompleteSelection: () -> Void

        init(
            onSelect: @escaping (SOSTrustedContact) -> Void,
            onIncompleteSelection: @escaping () -> Void
        ) {
            self.onSelect = onSelect
            self.onIncompleteSelection = onIncompleteSelection
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let phoneNumber = contact.phoneNumbers.first?.value.stringValue
            let emailAddress = contact.emailAddresses.first?.value as String?

            guard Self.cleaned(phoneNumber) != nil || Self.cleaned(emailAddress) != nil else {
                onIncompleteSelection()
                return
            }

            let formattedName = CNContactFormatter.string(from: contact, style: .fullName)
            let fallbackName = phoneNumber ?? emailAddress ?? "Trusted contact"
            var channels: Set<SOSTrustedContactChannel> = []
            if Self.cleaned(phoneNumber) != nil {
                channels.insert(.sms)
            }
            if Self.cleaned(emailAddress) != nil {
                channels.insert(.email)
            }

            onSelect(SOSTrustedContact(
                displayName: Self.cleaned(formattedName) ?? fallbackName,
                phoneNumber: phoneNumber,
                emailAddress: emailAddress,
                notificationChannels: channels.isEmpty ? [.sms] : channels,
                consentedAt: Date()
            ))
        }

        private static func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }
}

#Preview {
    NavigationStack {
        SOSTrustedContactsView()
            .environmentObject(SOSStore())
    }
}
