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

    // MARK: Trash state

    public var showTrashConfirmation: Bool = false
    public var isDeleting: Bool = false
    public var deleteProgress: Double = 0
    public var deleteError: GmailAPIError?

    /// Shown in the confirmation sheet and anywhere else the app communicates that permanent
    /// deletion must be done in Gmail directly.
    public static let permanentDeletionNote =
        "Tidy Gmail only moves emails to Trash — it never permanently deletes them. "
        + "To permanently delete, open Gmail in your browser and empty the Trash."

    // MARK: Export state

    public var showExportPrompt: Bool = false
    public var isExporting: Bool = false
    public var exportProgress: ExportProgress?
    public var exportError: Error?
    public var exportSummary: ExportSummary?

    // MARK: Private

    private let client: any GmailAPIClient
    private var nextPageToken: String?
    private var exportCoordinator: ExportCoordinator?

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

    // MARK: - Trash intent handler

    /// Move selected messages to Trash. Call from a Task so it can be cancelled by cancelling that Task.
    /// Permanent deletion is intentionally not supported — users must empty Trash in Gmail directly.
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

    // MARK: - Export intent handler

    /// Execute the export. Call from a Task so it can be cancelled by cancelling that Task.
    public func exportSelected(to destination: URL, passphrase: String) async {
        let ids = Array(selectedMessageIDs)
        guard !ids.isEmpty else { return }

        isExporting = true
        exportError = nil
        exportProgress = nil
        exportSummary = nil
        defer { isExporting = false }

        let coordinator = ExportCoordinator(client: client)
        do {
            let summary = try await coordinator.export(
                messageIDs: ids,
                destination: destination,
                passphrase: passphrase,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.exportProgress = progress
                    }
                }
            )
            exportSummary = summary
            selectedMessageIDs = []
        } catch is CancellationError {
            // Export was cancelled; DMG already cleaned up by coordinator
            exportError = nil
        } catch {
            exportError = error
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
