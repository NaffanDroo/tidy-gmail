import Foundation
@testable import TidyGmailCore

final class MockGmailAPIClient: GmailAPIClient, @unchecked Sendable {
    var searchResult: Result<([GmailMessage], String?), Error> = .success(([], nil))
    var fetchMessageResult: Result<GmailMessage, Error> = .failure(GmailAPIError.invalidResponse)
    var trashResult: Result<Void, Error> = .success(())
    var fetchRawMessageResult: Result<RawGmailMessage, Error> = .failure(GmailAPIError.invalidResponse)
    var fetchLabelsResult: Result<[GmailLabel], Error> = .success([])

    var searchCallCount = 0
    var lastSearchQuery: GmailSearchQuery?
    var lastPageToken: String?
    var trashedIDs: [String] = []
    var fetchRawMessageCallCount = 0
    var fetchedRawMessageIDs: [String] = []
    var fetchLabelsCallCount = 0

    func searchMessages(
        query: GmailSearchQuery,
        pageToken: String?
    ) async throws -> (messages: [GmailMessage], nextPageToken: String?) {
        searchCallCount += 1
        lastSearchQuery = query
        lastPageToken = pageToken
        let (messages, token) = try searchResult.get()
        return (messages: messages, nextPageToken: token)
    }

    func fetchMessage(id: String) async throws -> GmailMessage {
        try fetchMessageResult.get()
    }

    func fetchRawMessage(id: String) async throws -> RawGmailMessage {
        fetchRawMessageCallCount += 1
        fetchedRawMessageIDs.append(id)
        return try fetchRawMessageResult.get()
    }

    func fetchLabels() async throws -> [GmailLabel] {
        fetchLabelsCallCount += 1
        return try fetchLabelsResult.get()
    }

    func trashMessages(ids: [String]) async throws {
        try trashResult.get()
        trashedIDs.append(contentsOf: ids)
    }
}

// MARK: - Fixture factories

extension RawGmailMessage {
    static func fixture(
        id: String = "msg-1",
        sender: String = "sender@example.com",
        subject: String = "Test subject",
        date: String = "Thu, 14 Nov 2024 18:13:20 +0000",
        body: String = "Hello, world!",
        labelIds: [String] = ["INBOX"]
    ) -> RawGmailMessage {
        let rfc2822 = """
        From: \(sender)\r
        Subject: \(subject)\r
        Date: \(date)\r
        Message-ID: <\(id)@example.com>\r
        \r
        \(body)
        """
        return RawGmailMessage(
            id: id,
            rawData: Data(rfc2822.utf8),
            labelIds: labelIds
        )
    }
}

extension GmailMessage {
    static func fixture(
        id: String = "msg-1",
        threadID: String = "thread-1",
        from: String = "sender@example.com",
        subject: String = "Test subject",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        snippet: String = "This is a test snippet",
        sizeEstimate: Int = 4096
    ) -> GmailMessage {
        GmailMessage(
            id: id,
            threadID: threadID,
            from: from,
            subject: subject,
            date: date,
            snippet: snippet,
            sizeEstimate: sizeEstimate
        )
    }
}
