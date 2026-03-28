import Foundation

// MARK: - Domain model

/// A lightweight representation of a Gmail message suitable for list display.
public struct GmailMessage: Identifiable, Sendable, Equatable {
    public let id: String
    public let threadID: String
    public let from: String
    public let subject: String
    public let date: Date
    public let snippet: String
    public let sizeEstimate: Int  // bytes

    public init(
        id: String,
        threadID: String,
        from: String,
        subject: String,
        date: Date,
        snippet: String,
        sizeEstimate: Int
    ) {
        self.id = id
        self.threadID = threadID
        self.from = from
        self.subject = subject
        self.date = date
        self.snippet = snippet
        self.sizeEstimate = sizeEstimate
    }

    /// Human-readable file size (e.g. "42 KB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeEstimate), countStyle: .file)
    }
}

// MARK: - Search query

public struct GmailSearchQuery: Sendable, Equatable {
    public let rawQuery: String
    public let maxResults: Int

    public static let defaultMaxResults = 100

    public init(rawQuery: String, maxResults: Int = GmailSearchQuery.defaultMaxResults) {
        self.rawQuery = rawQuery
        self.maxResults = maxResults
    }

    /// Convenience: all mail newer than N days.
    public static func newerThan(days: Int) -> GmailSearchQuery {
        GmailSearchQuery(rawQuery: "newer_than:\(days)d")
    }
}
