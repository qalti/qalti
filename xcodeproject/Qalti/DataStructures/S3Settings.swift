import Foundation

struct S3Settings: Codable, Equatable {
    static let defaultPresignTTLSeconds = 3600
    static let maxPresignTTLSeconds = 604800
    static let minPresignTTLSeconds = 60

    let accessKeyId: String
    let secretAccessKey: String
    let region: String
    let bucket: String
    let presignTTLSeconds: Int

    var effectivePresignTTLSeconds: Int {
        let bounded = min(presignTTLSeconds, Self.maxPresignTTLSeconds)
        return max(bounded, Self.minPresignTTLSeconds)
    }
}
