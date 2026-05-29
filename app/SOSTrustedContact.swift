import Foundation
import Security

enum SOSTrustedContactChannel: String, Codable, CaseIterable, Hashable {
    case sms
    case phoneCall = "phone_call"
    case email

    var label: String {
        switch self {
        case .sms: "SMS"
        case .phoneCall: "Call"
        case .email: "Email"
        }
    }

    var iconName: String {
        switch self {
        case .sms: "message.fill"
        case .phoneCall: "phone.fill"
        case .email: "envelope.fill"
        }
    }
}

struct SOSTrustedContact: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var relationshipLabel: String?
    var phoneNumber: String?
    var emailAddress: String?
    var notificationChannels: Set<SOSTrustedContactChannel>
    var consentedAt: Date?
    var lastNotifiedAt: Date?
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        relationshipLabel: String? = nil,
        phoneNumber: String? = nil,
        emailAddress: String? = nil,
        notificationChannels: Set<SOSTrustedContactChannel> = [.sms],
        consentedAt: Date? = nil,
        lastNotifiedAt: Date? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName.trimmedForSOS
        self.relationshipLabel = relationshipLabel?.nilIfBlankForSOS
        self.phoneNumber = phoneNumber?.nilIfBlankForSOS
        self.emailAddress = emailAddress?.nilIfBlankForSOS?.lowercased()
        self.notificationChannels = notificationChannels
        self.consentedAt = consentedAt
        self.lastNotifiedAt = lastNotifiedAt
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var deliverableChannels: [SOSTrustedContactChannel] {
        notificationChannels
            .filter { channel in
                switch channel {
                case .sms, .phoneCall:
                    phoneNumber != nil
                case .email:
                    emailAddress != nil
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
    }

    var notificationTarget: SOSTrustedContactNotificationTarget? {
        guard isActive, !displayName.isEmpty, !deliverableChannels.isEmpty else {
            return nil
        }

        return SOSTrustedContactNotificationTarget(
            contactID: id,
            displayName: displayName,
            relationshipLabel: relationshipLabel,
            phoneNumber: phoneNumber,
            emailAddress: emailAddress,
            channels: deliverableChannels,
            consentedAt: consentedAt
        )
    }

    var initials: String {
        let pieces = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(pieces).uppercased()
        return value.isEmpty ? "?" : value
    }

    var isDeliverable: Bool {
        notificationTarget != nil
    }

    var destinationSummary: String {
        if let phoneNumber {
            return phoneNumber
        }
        if let emailAddress {
            return emailAddress
        }
        return "No alert route"
    }

    var channelSummary: String {
        let labels = deliverableChannels.map(\.label)
        return labels.isEmpty ? "Needs phone or email" : labels.joined(separator: ", ")
    }
}

struct SOSTrustedContactNotificationTarget: Codable, Equatable {
    var contactID: UUID
    var displayName: String
    var relationshipLabel: String?
    var phoneNumber: String?
    var emailAddress: String?
    var channels: [SOSTrustedContactChannel]
    var consentedAt: Date?

    var functionPayload: [String: Any] {
        var payload: [String: Any] = [
            "contact_id": contactID.uuidString,
            "display_name": displayName,
            "channels": channels.map(\.rawValue)
        ]

        if let relationshipLabel {
            payload["relationship_label"] = relationshipLabel
        }
        if let phoneNumber {
            payload["phone_number"] = phoneNumber
        }
        if let emailAddress {
            payload["email_address"] = emailAddress
        }
        if let consentedAt {
            payload["consented_at"] = SOSPayloadCoding.string(from: consentedAt)
        }

        return payload
    }

    var redactedPayload: [String: Any] {
        var payload: [String: Any] = [
            "contact_id": contactID.uuidString,
            "display_name": displayName,
            "channels": channels.map(\.rawValue)
        ]

        if let relationshipLabel {
            payload["relationship_label"] = relationshipLabel
        }
        if let phoneNumber {
            payload["phone_last4"] = String(phoneNumber.suffix(4))
        }
        if emailAddress != nil {
            payload["has_email_address"] = true
        }
        if let consentedAt {
            payload["consented_at"] = SOSPayloadCoding.string(from: consentedAt)
        }

        return payload
    }
}

final class SOSTrustedContactStore {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = Bundle.main.bundleIdentifier ?? "org.pulsetrackr.sos",
        account: String = "trusted_contacts"
    ) {
        self.service = service
        self.account = account
    }

    func loadContacts() throws -> [SOSTrustedContact] {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw SOSTrustedContactStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw SOSTrustedContactStoreError.unreadableData
        }

        return try decoder.decode([SOSTrustedContact].self, from: data)
    }

    func saveContacts(_ contacts: [SOSTrustedContact]) throws {
        let data = try encoder.encode(contacts)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SOSTrustedContactStoreError.keychain(updateStatus)
        }

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SOSTrustedContactStoreError.keychain(addStatus)
        }
    }

    func upsert(_ contact: SOSTrustedContact) throws {
        var contacts = try loadContacts()
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
        } else {
            contacts.append(contact)
        }
        try saveContacts(contacts)
    }

    func deleteContact(withID id: UUID) throws {
        let contacts = try loadContacts().filter { $0.id != id }
        try saveContacts(contacts)
    }

    func markNotified(contactIDs: [UUID], at date: Date = Date()) throws {
        guard !contactIDs.isEmpty else { return }
        let ids = Set(contactIDs)
        var contacts = try loadContacts()
        for index in contacts.indices where ids.contains(contacts[index].id) {
            contacts[index].lastNotifiedAt = date
        }
        try saveContacts(contacts)
    }

    func deleteAll() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SOSTrustedContactStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum SOSTrustedContactStoreError: Error, Equatable {
    case keychain(OSStatus)
    case unreadableData
}

private extension String {
    var trimmedForSOS: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlankForSOS: String? {
        let trimmed = trimmedForSOS
        return trimmed.isEmpty ? nil : trimmed
    }
}
