import Foundation

// MARK: - Label analysis result

/// Aggregated size and message count for a single Gmail label.
public struct LabelStat: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let messageCount: Int
    /// Total estimated bytes for all messages in this label.
    public let totalBytes: Int64

    public init(id: String, name: String, messageCount: Int, totalBytes: Int64) {
        self.id = id
        self.name = name
        self.messageCount = messageCount
        self.totalBytes = totalBytes
    }

    /// Human-readable total size (e.g. "42 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Gmail search query that pre-filters to this label in the email list view.
    public var searchQuery: String {
        switch id {
        case "INBOX":               return "in:inbox"
        case "SENT":                return "in:sent"
        case "TRASH":               return "in:trash"
        case "SPAM":                return "in:spam"
        case "STARRED":             return "is:starred"
        case "UNREAD":              return "is:unread"
        case "IMPORTANT":           return "is:important"
        case "CATEGORY_PROMOTIONS": return "category:promotions"
        case "CATEGORY_SOCIAL":     return "category:social"
        case "CATEGORY_UPDATES":    return "category:updates"
        case "CATEGORY_FORUMS":     return "category:forums"
        case "CATEGORY_PERSONAL":   return "category:personal"
        default:                    return "label:\(name)"
        }
    }
}
