import CryptoKit
import Foundation

// MARK: - Manifest writer

public enum ManifestWriter {
    /// Generate a `manifest.json` for the export archive.
    public static func write(
        messageIDs: [String],
        mboxFiles: [String: Data],
        exportDate: Date = Date()
    ) -> Data {
        let checksums = mboxFiles.mapValues { sha256Hex($0) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: exportDate)

        let manifest = ExportManifest(
            version: "1.0",
            exportDate: dateString,
            messageCount: messageIDs.count,
            messageIDs: messageIDs.sorted(),
            mboxChecksums: checksums
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // ExportManifest is always encodable; errors here are unrecoverable
        // swiftlint:disable:next force_try
        return try! encoder.encode(manifest)
    }

    /// Verify a manifest's checksums against actual MBOX file data.
    public static func verify(manifest: ExportManifest, mboxFiles: [String: Data]) -> Bool {
        for (filename, expectedChecksum) in manifest.mboxChecksums {
            guard let data = mboxFiles[filename] else { return false }
            if sha256Hex(data) != expectedChecksum { return false }
        }
        return true
    }

    // MARK: - Internal

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
