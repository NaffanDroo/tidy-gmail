import Foundation

// MARK: - API response types (Codable, internal — callers use GmailMessage)

struct GmailMessageListResponse: Decodable, Sendable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Decodable, Sendable {
    let id: String
    let threadId: String
}

struct GmailMessageResponse: Decodable, Sendable {
    let id: String
    let threadId: String
    let snippet: String?
    let sizeEstimate: Int?
    let payload: GmailMessagePayload?
}

struct GmailMessagePayload: Decodable, Sendable {
    let headers: [GmailHeader]?
}

struct GmailHeader: Decodable, Sendable {
    let name: String
    let value: String
}

// MARK: - Raw message response (format=raw)

struct GmailRawMessageResponse: Decodable, Sendable {
    let id: String
    let threadId: String
    let raw: String
    let labelIds: [String]?
}

// MARK: - Labels

struct GmailLabelsListResponse: Decodable, Sendable {
    let labels: [GmailLabelResponse]?
}

struct GmailLabelResponse: Decodable, Sendable {
    let id: String
    let name: String
}

// MARK: - Mapping

extension GmailMessageResponse {
    func toDomain() -> GmailMessage {
        let headers = payload?.headers ?? []

        func header(_ name: String) -> String {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value ?? ""
        }

        let dateString = header("Date")
        let date = DateFormatter.rfc2822.date(from: dateString) ?? Date.distantPast

        return GmailMessage(
            id: id,
            threadID: threadId,
            from: header("From"),
            subject: header("Subject"),
            date: date,
            snippet: snippet ?? "",
            sizeEstimate: sizeEstimate ?? 0
        )
    }
}

// MARK: - RFC 2822 date parsing

private extension DateFormatter {
    static let rfc2822: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
