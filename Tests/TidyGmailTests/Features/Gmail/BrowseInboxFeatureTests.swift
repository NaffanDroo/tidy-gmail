import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Browse inbox
//
// Scenarios covered:
//   - Search returns results — list is populated and sorted newest-first
//   - Search returns no results — message list is empty, no error shown
//   - API returns an error — error state is surfaced, messages cleared
//   - Results have a next page — hasMorePages is true
//   - Loading next page appends results and passes the page token
//   - Empty or whitespace query does not trigger a network call

@MainActor
final class BrowseInboxFeatureTests: XCTestCase {
    private var viewModel: EmailListViewModel!
    private var mockClient: MockGmailAPIClient!

    private let olderMessage = GmailMessage.fixture(
        id: "msg-old",
        date: Date(timeIntervalSince1970: 1_600_000_000)
    )
    private let newerMessage = GmailMessage.fixture(
        id: "msg-new",
        date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    override func setUp() {
        super.setUp()
        mockClient = MockGmailAPIClient()
        viewModel = EmailListViewModel(client: mockClient)
    }

    // MARK: - Scenario: search returns results

    func test_givenQuery_whenSearch_thenMessagesAreDisplayedSortedNewestFirst() async {
        // Given
        mockClient.searchResult = .success(([olderMessage, newerMessage], nil))
        viewModel.searchText = "from:newsletter@example.com"

        // When
        await viewModel.search()

        // Then
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.first?.id, "msg-new", "newest message should be first")
        XCTAssertEqual(viewModel.messages.last?.id, "msg-old")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func test_givenQuery_whenSearch_thenQueryIsPassedToClient() async {
        mockClient.searchResult = .success(([], nil))
        viewModel.searchText = "older_than:2y"
        await viewModel.search()
        XCTAssertEqual(mockClient.lastSearchQuery?.rawQuery, "older_than:2y")
    }

    // MARK: - Scenario: search returns no results

    func test_givenNoMatchingMessages_whenSearch_thenMessageListIsEmpty() async {
        // Given
        mockClient.searchResult = .success(([], nil))
        viewModel.searchText = "label:nonexistent"

        // When
        await viewModel.search()

        // Then
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Scenario: API error

    func test_givenAPIReturns401_whenSearch_thenUnauthorizedErrorIsSurfaced() async {
        // Given
        mockClient.searchResult = .failure(GmailAPIError.unauthorized)
        viewModel.searchText = "in:inbox"

        // When
        await viewModel.search()

        // Then
        XCTAssertEqual(viewModel.error, .unauthorized)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    // MARK: - Scenario: pagination

    func test_givenPageToken_whenSearch_thenHasMorePagesIsTrue() async {
        // Given
        mockClient.searchResult = .success(([newerMessage], "next-page-token"))
        viewModel.searchText = "in:all"

        // When
        await viewModel.search()

        // Then
        XCTAssertTrue(viewModel.hasMorePages)
    }

    func test_givenMultiplePages_whenLoadNextPage_thenMessagesAreAppendedAndPageTokenPassed() async {
        // Given — first page returns a token.
        let firstPageMessage = GmailMessage.fixture(id: "msg-p1")
        let secondPageMessage = GmailMessage.fixture(id: "msg-p2")

        mockClient.searchResult = .success(([firstPageMessage], "page-2-token"))
        viewModel.searchText = "in:all"
        await viewModel.search()

        // When — second page has no further token.
        mockClient.searchResult = .success(([secondPageMessage], nil))
        await viewModel.loadNextPage()

        // Then
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertTrue(viewModel.messages.map(\.id).contains("msg-p1"))
        XCTAssertTrue(viewModel.messages.map(\.id).contains("msg-p2"))
        XCTAssertFalse(viewModel.hasMorePages)
        XCTAssertEqual(mockClient.lastPageToken, "page-2-token")
    }

    // MARK: - Edge cases

    func test_givenWhitespaceQuery_whenSearch_thenNoNetworkCallIsMade() async {
        viewModel.searchText = "   "
        await viewModel.search()
        XCTAssertEqual(mockClient.searchCallCount, 0)
    }

    func test_givenPreviousResults_whenNewSearch_thenResultsAreCleared() async {
        mockClient.searchResult = .success(([newerMessage], nil))
        viewModel.searchText = "first query"
        await viewModel.search()
        XCTAssertEqual(viewModel.messages.count, 1)

        mockClient.searchResult = .success(([], nil))
        viewModel.searchText = "second query"
        await viewModel.search()
        XCTAssertTrue(viewModel.messages.isEmpty)
    }
}
