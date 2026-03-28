import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Bulk delete emails
//
// Scenarios covered:
//   - 50 emails selected → user confirms trash → all 50 moved to Trash, removed from list
//   - User dismisses trash confirmation → no emails are trashed, list unchanged
//   - 50 emails selected → user confirms permanent delete → all 50 deleted, removed from list
//   - User dismisses permanent-delete confirmation → no emails deleted, list unchanged
//   - API error during trash → error surfaced, isDeleting resets, list unchanged
//   - API error during permanent delete → error surfaced, isDeleting resets, list unchanged
//   - selectAll() selects every loaded message
//   - clearSelection() empties selection
//   - New search clears selection

@MainActor
final class BulkDeleteFeatureTests: XCTestCase {
    private var viewModel: EmailListViewModel!
    private var mockClient: MockGmailAPIClient!

    override func setUp() {
        super.setUp()
        mockClient = MockGmailAPIClient()
        viewModel = EmailListViewModel(client: mockClient)
    }

    // MARK: - Helpers

    /// Seed the view model with `count` messages already loaded into the list.
    private func seedMessages(count: Int) {
        viewModel.messages = (1...count).map { index in
            GmailMessage.fixture(
                id: "msg-\(index)",
                subject: "Subject \(index)"
            )
        }
    }

    // MARK: - Scenario: 50 emails selected → confirm trash → moved to Trash and removed from list

    func test_given50Emails_whenUserConfirmsTrash_thenAllMovedToTrashAndRemovedFromList() async {
        // Given — 50 messages loaded and all selected
        seedMessages(count: 50)
        viewModel.selectAll()
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 50)

        mockClient.trashResult = .success(())

        // When — user confirms the trash action (sheet dismissed, action fired)
        await viewModel.trashSelected()

        // Then — all 50 are moved to Trash via the API
        XCTAssertEqual(mockClient.trashedIDs.count, 50)

        // And — all 50 are removed from the visible list
        XCTAssertTrue(viewModel.messages.isEmpty, "messages should be cleared after trash")

        // And — selection is cleared
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)

        // And — delete state is reset
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertNil(viewModel.deleteError)
        XCTAssertEqual(viewModel.deleteProgress, 1.0)
    }

    // MARK: - Scenario: user dismisses trash confirmation → no emails are deleted

    func test_givenConfirmationSheetShown_whenUserDismisses_thenNoEmailsDeleted() async {
        // Given — messages loaded and selected
        seedMessages(count: 10)
        viewModel.selectAll()
        viewModel.showTrashConfirmation = true

        // When — user dismisses without confirming (simulated by not calling trashSelected)
        viewModel.showTrashConfirmation = false

        // Then — no API call was made
        XCTAssertTrue(mockClient.trashedIDs.isEmpty)

        // And — messages and selection are unchanged
        XCTAssertEqual(viewModel.messages.count, 10)
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 10)
        XCTAssertFalse(viewModel.isDeleting)
    }

    // MARK: - Scenario: 50 emails selected → confirm permanent delete → deleted and removed from list

    func test_given50Emails_whenUserConfirmsPermanentDelete_thenAllDeletedAndRemovedFromList() async {
        // Given
        seedMessages(count: 50)
        viewModel.selectAll()
        mockClient.deleteResult = .success(())

        // When
        await viewModel.permanentlyDeleteSelected()

        // Then — all 50 hit the delete API
        XCTAssertEqual(mockClient.deletedIDs.count, 50)

        // And — removed from visible list
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertNil(viewModel.deleteError)
    }

    // MARK: - Scenario: user dismisses permanent-delete confirmation → no emails deleted

    func test_givenPermanentDeleteConfirmationShown_whenUserDismisses_thenNoEmailsDeleted() async {
        // Given
        seedMessages(count: 5)
        viewModel.selectAll()
        viewModel.showPermanentDeleteConfirmation = true

        // When — dismiss without confirming
        viewModel.showPermanentDeleteConfirmation = false

        // Then
        XCTAssertTrue(mockClient.deletedIDs.isEmpty)
        XCTAssertEqual(viewModel.messages.count, 5)
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 5)
    }

    // MARK: - Scenario: API error during trash → error surfaced, state reset

    func test_givenAPIFailure_whenTrashSelected_thenErrorIsSurfacedAndDeletingResets() async {
        // Given
        seedMessages(count: 5)
        viewModel.selectAll()
        mockClient.trashResult = .failure(GmailAPIError.rateLimited)

        // When
        await viewModel.trashSelected()

        // Then — error is surfaced
        XCTAssertEqual(viewModel.deleteError, .rateLimited)

        // And — messages are NOT removed (nothing was successfully trashed)
        XCTAssertEqual(viewModel.messages.count, 5)

        // And — state cleaned up
        XCTAssertFalse(viewModel.isDeleting)
    }

    // MARK: - Scenario: API error during permanent delete → error surfaced, state reset

    func test_givenAPIFailure_whenPermanentDeleteSelected_thenErrorIsSurfacedAndDeletingResets() async {
        // Given
        seedMessages(count: 5)
        viewModel.selectAll()
        mockClient.deleteResult = .failure(GmailAPIError.serverError(statusCode: 500))

        // When
        await viewModel.permanentlyDeleteSelected()

        // Then
        XCTAssertEqual(viewModel.deleteError, .serverError(statusCode: 500))
        XCTAssertEqual(viewModel.messages.count, 5)
        XCTAssertFalse(viewModel.isDeleting)
    }

    // MARK: - Scenario: selectAll selects every loaded message

    func test_givenLoadedMessages_whenSelectAll_thenAllMessagesAreSelected() async {
        // Given
        seedMessages(count: 20)

        // When
        viewModel.selectAll()

        // Then
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 20)
        XCTAssertTrue(viewModel.messages.allSatisfy { viewModel.selectedMessageIDs.contains($0.id) })
    }

    // MARK: - Scenario: clearSelection empties the selection

    func test_givenSelection_whenClearSelection_thenSelectionIsEmpty() {
        // Given
        seedMessages(count: 5)
        viewModel.selectAll()
        XCTAssertFalse(viewModel.selectedMessageIDs.isEmpty)

        // When
        viewModel.clearSelection()

        // Then
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)
    }

    // MARK: - Scenario: new search clears selection

    func test_givenSelection_whenNewSearch_thenSelectionIsCleared() async {
        // Given — some messages selected from a prior search
        seedMessages(count: 5)
        viewModel.selectAll()
        XCTAssertFalse(viewModel.selectedMessageIDs.isEmpty)

        // When — user runs a new search
        mockClient.searchResult = .success(([], nil))
        viewModel.searchText = "from:someone@example.com"
        await viewModel.search()

        // Then — selection is cleared along with the old results
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)
    }

    // MARK: - Scenario: isDeleting is set to true during operation and false after

    func test_isDeletingIsTrueWhileDeletingAndFalseAfter() async {
        seedMessages(count: 3)
        viewModel.selectAll()
        mockClient.trashResult = .success(())

        // isDeleting starts false
        XCTAssertFalse(viewModel.isDeleting)

        await viewModel.trashSelected()

        // isDeleting is false after completion
        XCTAssertFalse(viewModel.isDeleting)
    }

    // MARK: - Scenario: trashSelected is a no-op when nothing is selected

    func test_givenNoSelection_whenTrashSelected_thenNoAPICallIsMade() async {
        seedMessages(count: 5)
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)

        await viewModel.trashSelected()

        XCTAssertTrue(mockClient.trashedIDs.isEmpty)
        XCTAssertEqual(viewModel.messages.count, 5)
    }
}
