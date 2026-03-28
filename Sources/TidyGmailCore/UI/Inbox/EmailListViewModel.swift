import Foundation
import Observation

// MARK: - View model

@MainActor
@Observable
public final class EmailListViewModel {
    // MARK: Browse state

    public var searchText: String = ""
    public var messages: [GmailMessage] = []
    public var isLoading: Bool = false
    public var isLoadingMore: Bool = false
    public var error: GmailAPIError?
    public var hasMorePages: Bool = false

    // MARK: Selection state

    public var selectedMessageIDs: Set<String> = []

    public var selectedMessages: [GmailMessage] {
        messages.filter { selectedMessageIDs.contains($0.id) }
    }

    // MARK: Delete state

    public var showTrashConfirmation: Bool = false
    public var showPermanentDeleteConfirmation: Bool = false
    public var isDeleting: Bool = false
    public var deleteProgress: Double = 0
    public var deleteError: GmailAPIError?

    // MARK: Private

    private let client: any GmailAPIClient
    private var nextPageToken: String?

    public init(client: any GmailAPIClient) {
        self.client = client
    }

    // MARK: - Browse intent handlers

    public func search() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        messages = []
        nextPageToken = nil
        error = nil
        selectedMessageIDs = []
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

    // MARK: - Selection intent handlers

    public func selectAll() {
        selectedMessageIDs = Set(messages.map(\.id))
    }

    public func clearSelection() {
        selectedMessageIDs = []
    }

    // MARK: - Delete intent handlers

    /// Move selected messages to Trash. Call from a Task so it can be cancelled by cancelling that Task.
    public func trashSelected() async {
        let ids = Array(selectedMessageIDs)
        guard !ids.isEmpty else { return }
        isDeleting = true
        deleteProgress = 0
        deleteError = nil
        defer { isDeleting = false }

        let batches = stride(from: 0, to: ids.count, by: 1_000).map {
            Array(ids[$0..<min($0 + 1_000, ids.count)])
        }
        var processed = 0
        do {
            for batch in batches {
                try Task.checkCancellation()
                try await client.trashMessages(ids: batch)
                processed += batch.count
                deleteProgress = Double(processed) / Double(ids.count)
            }
            // Remove trashed messages from the visible list.
            let trashedSet = Set(ids)
            messages.removeAll { trashedSet.contains($0.id) }
            selectedMessageIDs = []
        } catch is CancellationError {
            // Partially trashed emails stay in Trash — no rollback.
            let trashedIDs = Set(ids.prefix(processed))
            messages.removeAll { trashedIDs.contains($0.id) }
            selectedMessageIDs = selectedMessageIDs.subtracting(trashedIDs)
        } catch let apiError as GmailAPIError {
            deleteError = apiError
        } catch {
            deleteError = .invalidResponse
        }
    }

    /// Permanently delete selected messages. Call from a Task so it can be cancelled.
    public func permanentlyDeleteSelected() async {
        let ids = Array(selectedMessageIDs)
        guard !ids.isEmpty else { return }
        isDeleting = true
        deleteProgress = 0
        deleteError = nil
        defer { isDeleting = false }

        let batches = stride(from: 0, to: ids.count, by: 1_000).map {
            Array(ids[$0..<min($0 + 1_000, ids.count)])
        }
        var processed = 0
        do {
            for batch in batches {
                try Task.checkCancellation()
                try await client.deleteMessages(ids: batch)
                processed += batch.count
                deleteProgress = Double(processed) / Double(ids.count)
            }
            let deletedSet = Set(ids)
            messages.removeAll { deletedSet.contains($0.id) }
            selectedMessageIDs = []
        } catch is CancellationError {
            let deletedIDs = Set(ids.prefix(processed))
            messages.removeAll { deletedIDs.contains($0.id) }
            selectedMessageIDs = selectedMessageIDs.subtracting(deletedIDs)
        } catch let apiError as GmailAPIError {
            deleteError = apiError
        } catch {
            deleteError = .invalidResponse
        }
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
