import Foundation
import Observation

// MARK: - View model

@MainActor
@Observable
public final class LabelAnalysisViewModel {

    // MARK: - State

    public enum ScanState: Equatable, Sendable {
        case idle
        case scanning
        case complete
        case failed(String)
    }

    public var scanState: ScanState = .idle
    /// Labels completed so far, sorted largest-first. Updated progressively during scanning.
    public var stats: [LabelStat] = []
    /// Messages scanned so far across all completed labels.
    public var scannedCount: Int = 0
    /// Grand total of messages across all labels (from labels.list).
    public var totalMessages: Int = 0

    // MARK: - Private

    private let client: any GmailAPIClient

    public init(client: any GmailAPIClient) {
        self.client = client
    }

    // MARK: - Intent handlers

    /// Run the label analysis. Call from a `Task` so cancellation propagates correctly.
    /// If a scan is already in progress this method returns immediately without restarting.
    public func startAnalysis() async {
        guard scanState != .scanning else { return }
        scanState = .scanning
        stats = []
        scannedCount = 0
        totalMessages = 0

        let coordinator = LabelAnalysisCoordinator(client: client)
        do {
            let finalStats = try await coordinator.analyse { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stats = progress.completedStats
                    self.scannedCount = progress.scannedMessages
                    self.totalMessages = progress.totalMessages
                }
            }
            stats = finalStats
            scanState = .complete
        } catch is CancellationError {
            scanState = .idle
        } catch {
            scanState = .failed(error.localizedDescription)
        }
    }
}
