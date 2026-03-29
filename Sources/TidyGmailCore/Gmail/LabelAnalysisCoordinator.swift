import Foundation

// MARK: - Progress model

/// Snapshot of analysis progress delivered after each label completes.
public struct LabelAnalysisProgress: Sendable, Equatable {
    /// Labels completed so far, sorted largest-first.
    public let completedStats: [LabelStat]
    /// Total messages scanned across all completed labels.
    public let scannedMessages: Int
    /// Grand total of messages across all labels (from labels.list messagesTotal).
    /// May be 0 if the API did not return messagesTotal for any label.
    public let totalMessages: Int

    public var fraction: Double {
        guard totalMessages > 0 else { return 0 }
        return min(Double(scannedMessages) / Double(totalMessages), 1.0)
    }
}

// MARK: - Coordinator

/// Scans all Gmail labels and accumulates size estimates per label.
///
/// Uses bounded concurrency (default 4) to stay well within Gmail API quota
/// (250 quota units/second; messages.list costs 5 units per call).
/// Backs off with exponential retry on 429 (rate-limited) responses.
public final class LabelAnalysisCoordinator: Sendable {
    private let client: any GmailAPIClient
    private let concurrencyLimit: Int
    private let maxRetryAttempts: Int

    public init(
        client: any GmailAPIClient,
        concurrencyLimit: Int = 4,
        maxRetryAttempts: Int = 3
    ) {
        self.client = client
        self.concurrencyLimit = concurrencyLimit
        self.maxRetryAttempts = maxRetryAttempts
    }

    // MARK: - Public API

    /// Analyse all labels and return stats sorted by total size descending.
    ///
    /// `onProgress` is called after each label finishes — the callback may be invoked from a
    /// non-main-actor context; callers that update UI must dispatch back to the main actor.
    public func analyse(
        onProgress: @Sendable @escaping (LabelAnalysisProgress) -> Void
    ) async throws -> [LabelStat] {
        let labels = try await client.fetchLabels()
        guard !labels.isEmpty else { return [] }

        let totalMessages = labels.compactMap(\.messagesTotal).reduce(0, +)

        let stats: [LabelStat] = try await withThrowingTaskGroup(of: LabelStat.self) { group in
            var iterator = labels.makeIterator()
            var scannedMessages = 0
            var completed: [LabelStat] = []

            // Pre-fill up to the concurrency limit.
            for _ in 0..<min(concurrencyLimit, labels.count) {
                guard let label = iterator.next() else { break }
                group.addTask { try await self.analyseLabel(label) }
            }

            // As each label completes, admit the next one and report progress.
            while let stat = try await group.next() {
                completed.append(stat)
                scannedMessages += stat.messageCount

                onProgress(LabelAnalysisProgress(
                    completedStats: completed.sorted { $0.totalBytes > $1.totalBytes },
                    scannedMessages: scannedMessages,
                    totalMessages: totalMessages
                ))

                if let label = iterator.next() {
                    group.addTask { try await self.analyseLabel(label) }
                }
            }

            return completed
        }

        return stats.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Private

    private func analyseLabel(_ label: GmailLabel) async throws -> LabelStat {
        var totalBytes: Int64 = 0
        var messageCount = 0
        var pageToken: String?

        repeat {
            try Task.checkCancellation()
            let result = try await withExponentialRetry(maxAttempts: maxRetryAttempts) {
                try await self.client.fetchMessageSizes(labelId: label.id, pageToken: pageToken)
            }
            for ref in result.refs {
                totalBytes += Int64(ref.size)
                messageCount += 1
            }
            pageToken = result.nextPageToken
        } while pageToken != nil

        return LabelStat(
            id: label.id,
            name: label.name,
            messageCount: messageCount,
            totalBytes: totalBytes
        )
    }

    /// Retry helper that backs off on 429 (rateLimited) responses.
    /// Delays: attempt 0 → none, attempt 1 → 0.5 s, attempt 2 → 1 s, …
    private func withExponentialRetry<T>(
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error = GmailAPIError.rateLimited
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch GmailAPIError.rateLimited {
                lastError = GmailAPIError.rateLimited
                guard attempt < maxAttempts - 1 else { break }
                let delayNs = UInt64(pow(2.0, Double(attempt)) * 500_000_000)  // 0.5 s, 1 s, 2 s …
                try await Task.sleep(nanoseconds: delayNs)
            }
        }
        throw lastError
    }
}
