import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: MBOX writer (RFC 4155)
//
// Converts raw RFC 2822 messages into MBOX format with proper From_ separators
// and body escaping.

final class MBOXWriterTests: XCTestCase {

    private let testDate = Date(timeIntervalSince1970: 1_731_607_200) // 2024-11-14 18:00:00 UTC

    // MARK: - Scenario: single message produces valid MBOX output

    func test_givenSingleMessage_whenWritten_thenOutputHasFromLineAndBody() {
        let entry = MBOXEntry(
            sender: "alice@example.com",
            date: testDate,
            rawRFC2822: Data("Subject: Hello\r\n\r\nBody text".utf8)
        )

        let output = MBOXWriter.write(messages: [entry])
        let outputString = String(data: output, encoding: .utf8)!

        XCTAssertTrue(outputString.hasPrefix("From alice@example.com "))
        XCTAssertTrue(outputString.contains("Subject: Hello"))
        XCTAssertTrue(outputString.contains("Body text"))
    }

    // MARK: - Scenario: multiple messages are separated by blank lines

    func test_givenMultipleMessages_whenWritten_thenSeparatedByBlankLine() {
        let entries = [
            MBOXEntry(sender: "a@x.com", date: testDate, rawRFC2822: Data("Msg 1".utf8)),
            MBOXEntry(sender: "b@x.com", date: testDate, rawRFC2822: Data("Msg 2".utf8))
        ]

        let output = MBOXWriter.write(messages: entries)
        let outputString = String(data: output, encoding: .utf8)!

        // Each message ends with \n\n (body + blank separator)
        let fromLines = outputString.components(separatedBy: "\n").filter { $0.hasPrefix("From ") }
        XCTAssertEqual(fromLines.count, 2)
    }

    // MARK: - Scenario: "From " lines in body are escaped as ">From "

    func test_givenBodyWithFromLine_whenWritten_thenFromLineIsEscaped() {
        let bodyWithFrom = "First line\nFrom someone@example.com said hello\nLast line"
        let entry = MBOXEntry(
            sender: "test@example.com",
            date: testDate,
            rawRFC2822: Data(bodyWithFrom.utf8)
        )

        let output = MBOXWriter.write(messages: [entry])
        let outputString = String(data: output, encoding: .utf8)!

        XCTAssertTrue(outputString.contains(">From someone@example.com said hello"))
        XCTAssertFalse(
            outputString.components(separatedBy: "\n")
                .dropFirst() // Skip the From_ separator
                .contains(where: { $0.hasPrefix("From ") })
        )
    }

    // MARK: - Scenario: empty messages list produces empty output

    func test_givenNoMessages_whenWritten_thenOutputIsEmpty() {
        let output = MBOXWriter.write(messages: [])
        XCTAssertTrue(output.isEmpty)
    }

    // MARK: - Scenario: From_ date format matches MBOX convention

    func test_fromLineDateFormat() {
        let formatted = MBOXWriter.formatDate(testDate)
        // Should be like "Thu Nov 14 18:00:00 2024"
        XCTAssertTrue(formatted.contains("Nov"))
        XCTAssertTrue(formatted.contains("2024"))
    }

    // MARK: - Scenario: message ending without newline gets one appended

    func test_givenMessageWithoutTrailingNewline_whenWritten_thenNewlineAppended() {
        let entry = MBOXEntry(
            sender: "test@example.com",
            date: testDate,
            rawRFC2822: Data("No trailing newline".utf8)
        )

        let output = MBOXWriter.write(messages: [entry])
        let outputString = String(data: output, encoding: .utf8)!

        // Should end with double newline (body newline + separator)
        XCTAssertTrue(outputString.hasSuffix("\n\n"))
    }
}
