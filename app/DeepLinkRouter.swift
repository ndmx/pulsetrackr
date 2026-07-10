import Foundation

enum DeepLinkDestination: Equatable {
    case incident(id: String)
}

enum DeepLinkRouter {
    /// Populated by the share-link domain once chosen; empty accepts any host.
    static var allowedHosts: Set<String> = []

    static func destination(for url: URL) -> DeepLinkDestination? {
        switch url.scheme?.lowercased() {
        case "pulsetrackr":
            return customSchemeDestination(for: url)
        case "https":
            return universalLinkDestination(for: url)
        default:
            return nil
        }
    }

    private static func customSchemeDestination(for url: URL) -> DeepLinkDestination? {
        // pulsetrackr://incident/{id} → host is "incident", id is the first path component.
        guard url.host?.lowercased() == "incident" else { return nil }
        let components = pathComponents(of: url)
        guard components.count == 1, let id = components.first, isValidIncidentID(id) else {
            return nil
        }
        return .incident(id: id)
    }

    private static func universalLinkDestination(for url: URL) -> DeepLinkDestination? {
        // https://{host}/i/{id}
        if !allowedHosts.isEmpty {
            guard let host = url.host, allowedHosts.contains(host) else { return nil }
        }
        let components = pathComponents(of: url)
        guard components.count == 2,
              components[0] == "i",
              isValidIncidentID(components[1]) else {
            return nil
        }
        return .incident(id: components[1])
    }

    private static func pathComponents(of url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    // ASCII-only: Firestore doc ids we mint are hex/UUID-like; broader Unicode
    // "alphanumerics" would let lookalike ids through validation.
    private static let allowedIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    private static func isValidIncidentID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
    }
}
