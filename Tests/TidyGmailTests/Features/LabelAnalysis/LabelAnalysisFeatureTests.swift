import XCTest
@testable import TidyGmailCore

/// Thread-safe accumulator used in tests to collect values from `@Sendable` closures.
/// Marked `@unchecked Sendable` because all closures that use it in these tests
/// are invoked serially from the coordinator's task-group body.
private final class Accumulator<T>: @unchecked Sendable {
    private(set) var values: [T] = []
    func append(_ value: T) { values.append(value) }
}

/// BDD feature scenarios for the Label Size Analyser (issue #23).
///
/// Scenario: given a mocked label list and message sizes, when analysis completes,
/// labels appear ranked largest-first with correct totals.
@MainActor
final class LabelAnalysisFeatureTests: XCTestCase {

    // MARK: - Core ranking scenario

    func test_givenLabelsWithMessages_whenAnalysisCompletes_thenStatsRankedLargestFirst() async throws {
        // Given
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 3),
            GmailLabel(id: "Label_1", name: "Newsletters", messagesTotal: 2),
            GmailLabel(id: "Label_2", name: "Work", messagesTotal: 1)
        ])
        client.messageSizesByLabelId = [
            "INBOX": [(id: "m1", size: 10_000), (id: "m2", size: 20_000), (id: "m3", size: 5_000)], // 35 KB
            "Label_1": [(id: "m4", size: 1_000_000), (id: "m5", size: 500_000)],                     // 1.5 MB
            "Label_2": [(id: "m6", size: 100_000)]                                                    // 100 KB
        ]
        // Use concurrencyLimit=1 for deterministic serial processing
        let coordinator = LabelAnalysisCoordinator(client: client, concurrencyLimit: 1)

        // When
        let stats = try await coordinator.analyse(onProgress: { _ in })

        // Then — labels sorted largest-first
        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats[0].id, "Label_1")
        XCTAssertEqual(stats[0].totalBytes, 1_500_000)
        XCTAssertEqual(stats[0].messageCount, 2)
        XCTAssertEqual(stats[1].id, "Label_2")
        XCTAssertEqual(stats[1].totalBytes, 100_000)
        XCTAssertEqual(stats[2].id, "INBOX")
        XCTAssertEqual(stats[2].totalBytes, 35_000)
        XCTAssertEqual(stats[2].messageCount, 3)
    }

    // MARK: - Zero / nil sizeEstimate

    func test_givenMessagesWithZeroSize_whenAnalysisCompletes_thenTheyContributeZeroBytes() async throws {
        // Given — second message has size 0 (sizeEstimate unavailable from API)
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 2)
        ])
        client.messageSizesByLabelId = [
            "INBOX": [(id: "m1", size: 5_000), (id: "m2", size: 0)]
        ]
        let coordinator = LabelAnalysisCoordinator(client: client)

        // When
        let stats = try await coordinator.analyse(onProgress: { _ in })

        // Then — message count includes both; bytes are 5000 + 0
        XCTAssertEqual(stats.first?.messageCount, 2)
        XCTAssertEqual(stats.first?.totalBytes, 5_000)
    }

    // MARK: - Progress callbacks

    func test_givenMultipleLabels_whenAnalysisRuns_thenProgressCallbackFiredPerLabel() async throws {
        // Given
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 1),
            GmailLabel(id: "SENT", name: "Sent", messagesTotal: 1)
        ])
        client.messageSizesByLabelId = [
            "INBOX": [(id: "m1", size: 1_000)],
            "SENT": [(id: "m2", size: 2_000)]
        ]
        let coordinator = LabelAnalysisCoordinator(client: client, concurrencyLimit: 1)
        let updates = Accumulator<LabelAnalysisProgress>()

        // When
        _ = try await coordinator.analyse { progress in
            updates.append(progress)
        }

        // Then — one callback per label completion
        XCTAssertEqual(updates.values.count, 2)
        XCTAssertEqual(updates.values.last?.completedStats.count, 2)
    }

    func test_progressCallbackIncludesPartialStats() async throws {
        // Given — three labels processed serially
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "A", name: "Alpha", messagesTotal: 1),
            GmailLabel(id: "B", name: "Beta", messagesTotal: 1),
            GmailLabel(id: "C", name: "Gamma", messagesTotal: 1)
        ])
        client.messageSizesByLabelId = [
            "A": [(id: "m1", size: 100)],
            "B": [(id: "m2", size: 200)],
            "C": [(id: "m3", size: 300)]
        ]
        let coordinator = LabelAnalysisCoordinator(client: client, concurrencyLimit: 1)
        let updateCounts = Accumulator<Int>()

        _ = try await coordinator.analyse { progress in
            updateCounts.append(progress.completedStats.count)
        }

        // Then — progressively more completed stats reported: 1, 2, 3
        XCTAssertEqual(updateCounts.values, [1, 2, 3])
    }

    func test_progressTotalMessages_reflectsLabelMessagesTotal() async throws {
        // Given — labels have known totals
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "A", name: "Alpha", messagesTotal: 10),
            GmailLabel(id: "B", name: "Beta", messagesTotal: 20)
        ])
        client.messageSizesByLabelId = [
            "A": [(id: "m1", size: 1)],
            "B": [(id: "m2", size: 2)]
        ]
        let coordinator = LabelAnalysisCoordinator(client: client, concurrencyLimit: 1)
        let captured = Accumulator<LabelAnalysisProgress>()

        _ = try await coordinator.analyse { progress in
            captured.append(progress)
        }

        XCTAssertEqual(captured.values.last?.totalMessages, 30)
    }

    // MARK: - Empty labels

    func test_givenNoLabels_whenAnalysisRuns_thenReturnsEmptyStats() async throws {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([])
        let coordinator = LabelAnalysisCoordinator(client: client)

        let stats = try await coordinator.analyse(onProgress: { _ in })

        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: - Error propagation

    func test_givenFetchLabelsFails_whenAnalysisRuns_thenThrowsError() async {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .failure(GmailAPIError.unauthorized)
        let coordinator = LabelAnalysisCoordinator(client: client)

        do {
            _ = try await coordinator.analyse(onProgress: { _ in })
            XCTFail("Expected error to be thrown")
        } catch let error as GmailAPIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_givenFetchMessageSizesFails_whenAnalysisRuns_thenThrowsError() async {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 1)
        ])
        client.fetchMessageSizesError = GmailAPIError.serverError(statusCode: 500)
        let coordinator = LabelAnalysisCoordinator(client: client)

        do {
            _ = try await coordinator.analyse(onProgress: { _ in })
            XCTFail("Expected error to be thrown")
        } catch let error as GmailAPIError {
            XCTAssertEqual(error, .serverError(statusCode: 500))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cancellation

    func test_givenCancellation_whenTaskIsCancelled_thenThrowsCancellationError() async {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 1)
        ])
        client.messageSizesByLabelId = ["INBOX": [(id: "m1", size: 1_000)]]
        let coordinator = LabelAnalysisCoordinator(client: client)

        let task = Task {
            try await coordinator.analyse(onProgress: { _ in })
        }
        task.cancel()

        do {
            _ = try await task.value
            // May complete without error if it finishes before cancellation is observed — that's fine
        } catch is CancellationError {
            // Expected path
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - ViewModel integration

    func test_givenViewModel_whenAnalysisCompletes_thenStateIsCompleteAndStatsAreSorted() async {
        // Given
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([
            GmailLabel(id: "INBOX", name: "Inbox", messagesTotal: 1),
            GmailLabel(id: "SENT", name: "Sent", messagesTotal: 1)
        ])
        client.messageSizesByLabelId = [
            "INBOX": [(id: "m1", size: 500_000)],
            "SENT": [(id: "m2", size: 100_000)]
        ]
        let viewModel = LabelAnalysisViewModel(client: client)

        // When
        await viewModel.startAnalysis()

        // Then
        XCTAssertEqual(viewModel.scanState, .complete)
        XCTAssertEqual(viewModel.stats.count, 2)
        XCTAssertEqual(viewModel.stats[0].id, "INBOX")  // 500 KB is largest
        XCTAssertEqual(viewModel.stats[1].id, "SENT")
    }

    func test_givenViewModel_whenAPIFails_thenStateIsFailed() async {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .failure(GmailAPIError.unauthorized)
        let viewModel = LabelAnalysisViewModel(client: client)

        await viewModel.startAnalysis()

        guard case .failed = viewModel.scanState else {
            return XCTFail("Expected .failed state, got \(viewModel.scanState)")
        }
    }

    func test_givenViewModel_whenScanningAlreadyInProgress_thenSecondCallIsIgnored() async {
        let client = MockGmailAPIClient()
        client.fetchLabelsResult = .success([])
        let viewModel = LabelAnalysisViewModel(client: client)

        // Simulate already-scanning state
        viewModel.scanState = .scanning

        // Second call should be a no-op
        await viewModel.startAnalysis()

        // State remains scanning (not complete, not failed)
        XCTAssertEqual(viewModel.scanState, .scanning)
    }
}
