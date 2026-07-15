import Foundation

enum ShareConfig {
    /// Replace with the Firebase Hosting domain when chosen, and add it to DeepLinkRouter.allowedHosts at the same time.
    static let shareBaseURL = URL(string: "https://pulsetrackr.example")!

    /// `{shareBaseURL}/i/{docID}` where docID is the remote document id, or the local UUID lowercased.
    static func shareURL(for incident: Incident) -> URL? {
        let docID = incident.remoteDocumentID ?? incident.id.uuidString.lowercased()
        var components = URLComponents(url: shareBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/i/\(docID)"
        return components?.url
    }
}
