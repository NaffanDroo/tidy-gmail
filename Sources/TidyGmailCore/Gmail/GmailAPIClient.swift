import Foundation

// MARK: - Protocol

public protocol GmailAPIClient: Sendable {
    /// Search messages and return one page of results plus an optional continuation token.
    func searchMessages(
        query: GmailSearchQuery,
        pageToken: String?
    ) async throws -> (messages: [GmailMessage], nextPageToken: String?)

    /// Fetch full header details for a single message.
    func fetchMessage(id: String) async throws -> GmailMessage

    /// Move messages to Trash. IDs are sent in a single batchModify call (max 1 000 per call).
    /// This is the only deletion operation Tidy Gmail performs — permanent deletion is intentionally
    /// not supported; users must empty Trash in Gmail directly.
    func trashMessages(ids: [String]) async throws
}

// MARK: - Errors

public enum GmailAPIError: Error, Equatable {
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int)
    case decodingFailed
    case invalidResponse
}

// MARK: - Live implementation

public final class LiveGmailAPIClient: GmailAPIClient {
    private let session: URLSession
    private let tokenProvider: any TokenProvider
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    /// Maximum number of fetchMessage HTTP calls in-flight at once — prevents HTTP 429 from Gmail.
    private let fetchConcurrencyLimit = 5

    public init(session: URLSession = .shared, tokenProvider: any TokenProvider) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public func searchMessages(
        query: GmailSearchQuery,
        pageToken: String?
    ) async throws -> (messages: [GmailMessage], nextPageToken: String?) {
        var components = URLComponents(url: baseURL.appendingPathComponent("messages"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "q", value: query.rawQuery),
            URLQueryItem(name: "maxResults", value: String(query.maxResults))
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems

        let listResponse: GmailMessageListResponse = try await fetch(url: components.url!)

        guard let refs = listResponse.messages, !refs.isEmpty else {
            return (messages: [], nextPageToken: nil)
        }

        // Fetch headers for each message with bounded concurrency to avoid HTTP 429.
        let messages = try await withThrowingTaskGroup(of: GmailMessage.self) { group in
            var iterator = refs.prefix(50).makeIterator()

            // Pre-fill up to the concurrency limit.
            for _ in 0..<fetchConcurrencyLimit {
                guard let ref = iterator.next() else { break }
                group.addTask { try await self.fetchMessage(id: ref.id) }
            }

            // As each task completes, admit the next one from the queue.
            var collected = [GmailMessage]()
            while let message = try await group.next() {
                collected.append(message)
                if let ref = iterator.next() {
                    group.addTask { try await self.fetchMessage(id: ref.id) }
                }
            }
            return collected
        }

        return (
            messages: messages.sorted { $0.date > $1.date },
            nextPageToken: listResponse.nextPageToken
        )
    }

    public func trashMessages(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let url = baseURL.appendingPathComponent("messages/batchModify")
        let body = try JSONEncoder().encode(BatchModifyRequest(
            ids: ids,
            addLabelIds: ["TRASH"],
            removeLabelIds: ["INBOX"]
        ))
        try await post(url: url, body: body)
    }

    public func fetchMessage(id: String) async throws -> GmailMessage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("messages/\(id)"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]

        let response: GmailMessageResponse = try await fetch(url: components.url!)
        return response.toDomain()
    }

    // MARK: - Private

    private func post(url: URL, body: Data) async throws {
        let accessToken = try await tokenProvider.freshAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401:
            throw GmailAPIError.unauthorized
        case 429:
            throw GmailAPIError.rateLimited
        default:
            throw GmailAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        let accessToken = try await tokenProvider.freshAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw GmailAPIError.decodingFailed
            }
        case 401:
            throw GmailAPIError.unauthorized
        case 429:
            throw GmailAPIError.rateLimited
        default:
            throw GmailAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - User-facing error messages

extension GmailAPIError {
    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign out and sign in again."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError(let code):
            return "Gmail returned an error (HTTP \(code)). Please try again."
        case .decodingFailed, .invalidResponse:
            return "Received an unexpected response from Gmail. Please try again."
        }
    }
}

// MARK: - Batch request bodies

private struct BatchModifyRequest: Encodable {
    let ids: [String]
    let addLabelIds: [String]
    let removeLabelIds: [String]
}
