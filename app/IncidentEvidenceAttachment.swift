import Foundation

enum IncidentEvidenceKind: String {
    case photo
    case voice
}

struct IncidentEvidenceAttachment {
    var kind: IncidentEvidenceKind
    var filename: String
    var contentType: String
    var data: Data
    var durationSeconds: TimeInterval?
}

struct UploadedIncidentEvidence {
    var kind: IncidentEvidenceKind
    var storagePath: String
    var contentType: String
    var sizeBytes: Int
    var durationSeconds: TimeInterval?

    var payload: [String: Any] {
        var body: [String: Any] = [
            "kind": kind.rawValue,
            "storage_path": storagePath,
            "content_type": contentType,
            "size_bytes": sizeBytes
        ]
        if let durationSeconds {
            body["duration_seconds"] = durationSeconds
        }
        return body
    }
}
