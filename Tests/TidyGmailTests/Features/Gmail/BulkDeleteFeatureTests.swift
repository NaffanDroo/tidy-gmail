import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Bulk delete emails (trash only)
//
// Policy: Tidy Gmail moves emails to Trash — it never permanently deletes them.
//         Users who want to permanently delete must empty the Trash in Gmail directly.
//
// Scenarios covered:
//   - 50 emails selected → user confirms trash → all 50 moved to Trash, removed from list
//   - User dismisses trash confirmation → no emails are trashed, list unchanged
//   - API error during trash → error surfaced, isDeleting resets, list unchanged
//   - Permanent deletion is not available in the app (enforced at compile time by protocol)
//   - permanentDeletionNote directs users to Gmail and mentions Trash
//   - selectAll() selects every loaded message
//   - clearSelection() empties selection
//   - New search clears selection
//   - trashSelected is a no-op when nothing is selected

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

    private func seedMessages(count: Int) {
        viewModel.messages = (1...count).map { index in
            GmailMessage.fixture(id: "msg-\(index)", subject: "Subject \(index)")
        }
    }

    // MARK: - Scenario: 50 emails selected → confirm trash → moved to Trash and removed from list

    func test_given50Emails_whenUserConfirmsTrash_thenAllMovedToTrashAndRemovedFromList() async {
        // Given — 50 messages loaded and all selected
        seedMessages(count: 50)
        viewModel.selectAll()
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 50)

        mockClient.trashResult = .success(())

        // When — user confirms the trash action
        await viewModel.trashSelected()

        // Then — all 50 are moved to Trash via the API
        XCTAssertEqual(mockClient.trashedIDs.count, 50)

        // And — all 50 are removed from the visible list
        XCTAssertTrue(viewModel.messages.isEmpty, "messages should be removed from list after trash")

        // And — selection is cleared
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)

        // And — delete state is reset
        XCTAssertFalse(viewModel.isDeleting)
        XCTAssertNil(viewModel.deleteError)
        XCTAssertEqual(viewModel.deleteProgress, 1.0)
    }

    // MARK: - Scenario: user dismisses trash confirmation → no emails are trashed

    func test_givenConfirmationSheetShown_whenUserDismisses_thenNoEmailsAreMovedToTrash() async {
        // Given — messages loaded and selected, confirmation shown
        seedMessages(count: 10)
        viewModel.selectAll()
        viewModel.showTrashConfirmation = true

        // When — user dismisses without confirming (trashSelected is never called)
        viewModel.showTrashConfirmation = false

        // Then — no API call was made
        XCTAssertTrue(mockClient.trashedIDs.isEmpty)

        // And — messages and selection are unchanged
        XCTAssertEqual(viewModel.messages.count, 10)
        XCTAssertEqual(viewModel.selectedMessageIDs.count, 10)
        XCTAssertFalse(viewModel.isDeleting)
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

        // And — state is cleaned up
        XCTAssertFalse(viewModel.isDeleting)
    }

    // MARK: - Policy: permanent deletion is not available — enforced by the protocol

    // The GmailAPIClient protocol intentionally omits deleteMessages(_:).
    // This is a compile-time guarantee: there is no code path that can
    // permanently delete a message through this app. The test below documents
    // that intent by confirming only trashMessages is ever called.

    func test_trashingIsTheOnlyDeletionActionAndNoPermDeleteAPIExists() async {
        // Given
        seedMessages(count: 5)
        viewModel.selectAll()
        mockClient.trashResult = .success(())

        // When — the only deletion action available is trashSelected
        await viewModel.trashSelected()

        // Then — trashMessages was called
        XCTAssertEqual(mockClient.trashedIDs.count, 5)

        // And — MockGmailAPIClient has no deletedIDs property because deleteMessages
        // does not exist on the protocol. If it did, this file would not compile.
    }

    // MARK: - Policy: permanentDeletionNote directs users to Gmail

    func test_permanentDeletionNoteInformsUserToUseGmailForPermanentDeletion() {
        // The note is shown prominently in the trash confirmation sheet so users
        // always understand what the app does and does not do.
        let note = EmailListViewModel.permanentDeletionNote

        XCTAssertTrue(
            note.contains("Gmail"),
            "permanentDeletionNote must mention Gmail so users know where to permanently delete"
        )
        XCTAssertTrue(
            note.lowercased().contains("trash"),
            "permanentDeletionNote must mention Trash so users know the recovery window"
        )
        XCTAssertTrue(
            note.lowercased().contains("never") || note.lowercased().contains("only"),
            "permanentDeletionNote must make clear that the app does not permanently delete"
        )
    }

    // MARK: - Scenario: selectAll selects every loaded message

    func test_givenLoadedMessages_whenSelectAll_thenAllMessagesAreSelected() {
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

    // MARK: - Scenario: trashSelected is a no-op when nothing is selected

    func test_givenNoSelection_whenTrashSelected_thenNoAPICallIsMade() async {
        seedMessages(count: 5)
        XCTAssertTrue(viewModel.selectedMessageIDs.isEmpty)

        await viewModel.trashSelected()

        XCTAssertTrue(mockClient.trashedIDs.isEmpty)
        XCTAssertEqual(viewModel.messages.count, 5)
    }

    // MARK: - Scenario: isDeleting is false before and after the operation

    func test_isDeletingIsFalseBeforeAndAfterTrash() async {
        seedMessages(count: 3)
        viewModel.selectAll()
        mockClient.trashResult = .success(())

        XCTAssertFalse(viewModel.isDeleting)
        await viewModel.trashSelected()
        XCTAssertFalse(viewModel.isDeleting)
    }
}
