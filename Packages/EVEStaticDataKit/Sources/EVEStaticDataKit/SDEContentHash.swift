import CryptoKit
import Foundation

enum SDEContentHash {
    static func make(
        buildNumber: Int,
        descriptors: [SDEDatasetDescriptor]
    ) -> String {
        let canonical = descriptors.map { descriptor in
            [
                descriptor.kind.rawValue,
                descriptor.fileName,
                String(descriptor.recordCount),
                String(descriptor.byteCount),
                descriptor.sha256
            ].joined(separator: ":")
        }.joined(separator: "|")
        return SHA256.hash(
            data: Data("\(buildNumber)|\(canonical)".utf8)
        ).hexString
    }
}

extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
