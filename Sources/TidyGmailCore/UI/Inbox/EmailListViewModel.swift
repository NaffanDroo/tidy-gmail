import Foundation
import Observation

// MARK: - View model

@MainActor
@Observable
public final class EmailListViewModel {
    // MARK: State

    public var searchText: String = ""
    public var messages: [GmailMessage] = []
    public var isLoading: Bool = false
    public var isLoadingMore: Bool = false
    public var error: GmailAPIError?
    public var hasMorePages: Bool = false

    // MARK: Private

    private let client: any GmailAPIClient
    private var nextPageToken: String?

    public init(client: any GmailAPIClient = LiveGmailAPIClient()) {
        self.client = client
    }

    // MARK: - Intent handlers

    public func search() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        messages = []
        nextPageToken = nil
        error = nil
        isLoading = true
        defer { isLoading = false }

        await loadPage()
    }

    public func loadNextPage() async {
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        await loadPage()
    }

    // MARK: - Private

    private func loadPage() async {
        let query = GmailSearchQuery(rawQuery: searchText)
        do {
            let result = try await client.searchMessages(query: query, pageToken: nextPageToken)
            messages.append(contentsOf: result.messages.sorted { $0.date > $1.date })
            nextPageToken = result.nextPageToken
            hasMorePages = result.nextPageToken != nil
        } catch let apiError as GmailAPIError {
            error = apiError
        } catch {
            self.error = .invalidResponse
        }
    }
}
