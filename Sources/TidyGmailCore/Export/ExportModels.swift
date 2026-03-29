import Foundation

// MARK: - Raw message from Gmail API (format=raw)

public struct RawGmailMessage: Sendable, Equatable {
    public let id: String
    public let rawData: Data  // Decoded RFC 2822 email bytes
    public let labelIds: [String]

    public init(id: String, rawData: Data, labelIds: [String]) {
        self.id = id
        self.rawData = rawData
        self.labelIds = labelIds
    }
}

// MARK: - Gmail label

public struct GmailLabel: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Total messages in this label as reported by the Gmail API labels.list endpoint.
    /// Used by the label analyser to show overall progress; may be nil for labels
    /// that don't report this field.
    public let messagesTotal: Int?

    public init(id: String, name: String, messagesTotal: Int? = nil) {
        self.id = id
        self.name = name
        self.messagesTotal = messagesTotal
    }
}

// MARK: - Export manifest

public struct ExportManifest: Codable, Sendable, Equatable {
    public let version: String
    public let exportDate: String
    public let messageCount: Int
    public let messageIDs: [String]
    public let mboxChecksums: [String: String]  // filename -> SHA-256 hex

    public init(
        version: String = "1.0",
        exportDate: String,
        messageCount: Int,
        messageIDs: [String],
        mboxChecksums: [String: String]
    ) {
        self.version = version
        self.exportDate = exportDate
        self.messageCount = messageCount
        self.messageIDs = messageIDs
        self.mboxChecksums = mboxChecksums
    }
}

// MARK: - Export progress

public struct ExportProgress: Sendable, Equatable {
    public let phase: Phase
    public let current: Int
    public let total: Int

    public enum Phase: Sendable, Equatable {
        case fetchingMessages
        case writingArchive
        case creatingDMG
        case complete
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    public var description: String {
        switch phase {
        case .fetchingMessages:
            return "Fetching email \(current) of \(total)\u{2026}"
        case .writingArchive:
            return "Writing archive\u{2026}"
        case .creatingDMG:
            return "Creating encrypted disk image\u{2026}"
        case .complete:
            return "Export complete"
        }
    }
}

// MARK: - Export summary

public struct ExportSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let filePath: URL
    public let fileSize: Int64
    public let messageCount: Int

    public init(filePath: URL, fileSize: Int64, messageCount: Int) {
        self.id = filePath.lastPathComponent
        self.filePath = filePath
        self.fileSize = fileSize
        self.messageCount = messageCount
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Export error

public enum ExportError: Error, Equatable, Sendable {
    case noMessagesSelected
    case invalidPassphrase(String)
    case fetchFailed(String)
    case dmgCreationFailed(String)
    case cancelled
    case fileSystemError(String)
}

extension ExportError {
    public var userMessage: String {
        switch self {
        case .noMessagesSelected:
            return "No emails are selected for export."
        case .invalidPassphrase(let reason):
            return "Invalid passphrase: \(reason)"
        case .fetchFailed(let detail):
            return "Failed to fetch emails: \(detail)"
        case .dmgCreationFailed(let detail):
            return "Failed to create encrypted archive: \(detail)"
        case .cancelled:
            return "Export was cancelled."
        case .fileSystemError(let detail):
            return "File system error: \(detail)"
        }
    }
}
