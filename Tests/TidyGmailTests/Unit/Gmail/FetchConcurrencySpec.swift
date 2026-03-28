import XCTest
@testable import TidyGmailCore

// Feature: Rate-limit back-pressure in searchMessages
//
// Scenarios covered:
//   - With 20 message refs, peak concurrent fetchMessage calls never exceeds 5

final class FetchConcurrencyTests: XCTestCase {

    // MARK: - Scenario: peak concurrency is capped at 5

    func test_givenTwentyMessageRefs_whenSearchMessages_thenPeakConcurrencyIsAtMostFive() async throws {
        // Given
        let tracker = ConcurrencyTracker()
        ConcurrencyTrackingURLProtocol.tracker = tracker

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConcurrencyTrackingURLProtocol.self]
        let session = URLSession(configuration: config)

        let tokenProvider = StubTokenProvider()
        let client = LiveGmailAPIClient(session: session, tokenProvider: tokenProvider)

        // When
        _ = try await client.searchMessages(
            query: GmailSearchQuery(rawQuery: "in:inbox", maxResults: 20),
            pageToken: nil
        )

        // Then
        XCTAssertLessThanOrEqual(
            tracker.peakConcurrency,
            5,
            "Expected at most 5 concurrent fetchMessage calls but saw \(tracker.peakConcurrency)"
        )
        XCTAssertGreaterThanOrEqual(
            tracker.peakConcurrency,
            1,
            "Expected at least 1 concurrent call"
        )
    }
}

// MARK: - Test doubles

/// Thread-safe peak-concurrency tracker.
final class ConcurrencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peakConcurrency = 0

    func enter() {
        lock.lock()
        defer { lock.unlock() }
        current += 1
        if current > peakConcurrency { peakConcurrency = current }
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        current -= 1
    }
}

/// A URLProtocol that:
/// - For the list request (path ends in "/messages") → returns 20 message refs.
/// - For individual message requests → increments the concurrency counter,
///   yields briefly so other tasks can accumulate, then returns a valid message response.
final class ConcurrencyTrackingURLProtocol: URLProtocol, @unchecked Sendable {
    static var tracker: ConcurrencyTracker!

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path

        // List request: /gmail/v1/users/me/messages (but not a specific message)
        if path.hasSuffix("/messages") && !path.contains("/messages/") {
            let refs = (1...20).map { idx in
                """
                {"id":"msg-\(idx)","threadId":"thread-\(idx)"}
                """
            }.joined(separator: ",")
            let json = """
            {"messages":[\(refs)],"resultSizeEstimate":20}
            """
            respond(with: json)
            return
        }

        // Individual message fetch — run on background thread so URLSession tasks overlap.
        let capturedClient = client
        let capturedRequest = request
        DispatchQueue.global().async {
            ConcurrencyTrackingURLProtocol.tracker.enter()
            // Hold briefly so concurrent tasks can accumulate before the first one finishes.
            Thread.sleep(forTimeInterval: 0.02)
            ConcurrencyTrackingURLProtocol.tracker.leave()

            let msgID = capturedRequest.url?.pathComponents.last ?? "unknown"
            let json = """
            {
              "id": "\(msgID)",
              "threadId": "thread-1",
              "snippet": "test",
              "sizeEstimate": 1024,
              "payload": {
                "headers": [
                  {"name": "From", "value": "sender@example.com"},
                  {"name": "Subject", "value": "Test"},
                  {"name": "Date", "value": "Mon, 01 Jan 2024 00:00:00 +0000"}
                ]
              }
            }
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: capturedRequest.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            capturedClient?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            capturedClient?.urlProtocol(self, didLoad: data)
            capturedClient?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private func respond(with json: String) {
        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Minimal TokenProvider that always returns a dummy token.
struct StubTokenProvider: TokenProvider {
    func freshAccessToken() async throws -> String { "stub-token" }
}
