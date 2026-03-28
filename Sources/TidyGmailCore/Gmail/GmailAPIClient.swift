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
    private let keychain: any KeychainService
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    public init(session: URLSession = .shared, keychain: any KeychainService = LiveKeychainService()) {
        self.session = session
        self.keychain = keychain
    }

    public func searchMessages(
        query: GmailSearchQuery,
        pageToken: String?
    ) async throws -> (messages: [GmailMessage], nextPageToken: String?) {
        var components = URLComponents(url: baseURL.appendingPathComponent("messages"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "q", value: query.rawQuery),
            URLQueryItem(name: "maxResults", value: String(query.maxResults)),
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems

        let listResponse: GmailMessageListResponse = try await fetch(url: components.url!)

        guard let refs = listResponse.messages, !refs.isEmpty else {
            return (messages: [], nextPageToken: nil)
        }

        // Fetch headers for each message in parallel (capped at 50 concurrent to respect rate limits).
        let messages = try await withThrowingTaskGroup(of: GmailMessage.self) { group in
            for ref in refs.prefix(50) {
                group.addTask { try await self.fetchMessage(id: ref.id) }
            }
            return try await group.reduce(into: [GmailMessage]()) { $0.append($1) }
        }

        return (
            messages: messages.sorted { $0.date > $1.date },
            nextPageToken: listResponse.nextPageToken
        )
    }

    public func fetchMessage(id: String) async throws -> GmailMessage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("messages/\(id)"),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "metadata"),
                                  URLQueryItem(name: "metadataHeaders", value: "From"),
                                  URLQueryItem(name: "metadataHeaders", value: "Subject"),
                                  URLQueryItem(name: "metadataHeaders", value: "Date")]

        let response: GmailMessageResponse = try await fetch(url: components.url!)
        return response.toDomain()
    }

    // MARK: - Private

    private func fetch<T: Decodable>(url: URL) async throws -> T {
        guard let accessToken = try keychain.retrieve(forKey: OAuthConfiguration.KeychainKey.accessToken) else {
            throw GmailAPIError.unauthorized
        }

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
