import XCTest
@testable import TidyGmailCore

final class LabelStatTests: XCTestCase {

    // MARK: - formattedSize

    func test_formattedSize_bytes() {
        let stat = LabelStat(id: "1", name: "Test", messageCount: 1, totalBytes: 512)
        XCTAssertEqual(stat.formattedSize, "512 bytes")
    }

    func test_formattedSize_kilobytes() {
        let stat = LabelStat(id: "1", name: "Test", messageCount: 1, totalBytes: 5_120)
        XCTAssertTrue(stat.formattedSize.contains("KB") || stat.formattedSize.contains("kB"),
                      "Expected KB unit, got: \(stat.formattedSize)")
    }

    func test_formattedSize_megabytes() {
        let stat = LabelStat(id: "1", name: "Test", messageCount: 100, totalBytes: 5_242_880)
        XCTAssertTrue(stat.formattedSize.contains("MB"),
                      "Expected MB unit, got: \(stat.formattedSize)")
    }

    func test_formattedSize_gigabytes() {
        let stat = LabelStat(id: "1", name: "Test", messageCount: 10_000, totalBytes: 2_147_483_648)
        XCTAssertTrue(stat.formattedSize.contains("GB"),
                      "Expected GB unit, got: \(stat.formattedSize)")
    }

    func test_formattedSize_zero() {
        let stat = LabelStat(id: "1", name: "Test", messageCount: 0, totalBytes: 0)
        XCTAssertFalse(stat.formattedSize.isEmpty)
    }

    func test_formattedSize_differentiatesSizes() {
        let small = LabelStat(id: "1", name: "A", messageCount: 1, totalBytes: 1_000)
        let large = LabelStat(id: "2", name: "B", messageCount: 100, totalBytes: 1_000_000_000)
        XCTAssertNotEqual(small.formattedSize, large.formattedSize)
    }

    // MARK: - Sorting

    func test_sortedByTotalBytesDescending() {
        let stats = [
            LabelStat(id: "1", name: "Small", messageCount: 5, totalBytes: 1_000),
            LabelStat(id: "2", name: "Large", messageCount: 50, totalBytes: 1_000_000),
            LabelStat(id: "3", name: "Medium", messageCount: 20, totalBytes: 50_000)
        ]
        let sorted = stats.sorted { $0.totalBytes > $1.totalBytes }
        XCTAssertEqual(sorted.map(\.name), ["Large", "Medium", "Small"])
    }

    func test_sortedByTotalBytes_handlesAllZero() {
        let stats = [
            LabelStat(id: "1", name: "A", messageCount: 10, totalBytes: 0),
            LabelStat(id: "2", name: "B", messageCount: 5, totalBytes: 0)
        ]
        let sorted = stats.sorted { $0.totalBytes > $1.totalBytes }
        // Both have same size — order is stable (original order preserved)
        XCTAssertEqual(sorted.map(\.id), ["1", "2"])
    }

    // MARK: - searchQuery (system labels)

    func test_searchQuery_inbox() {
        let stat = LabelStat(id: "INBOX", name: "Inbox", messageCount: 100, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "in:inbox")
    }

    func test_searchQuery_sent() {
        let stat = LabelStat(id: "SENT", name: "Sent", messageCount: 50, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "in:sent")
    }

    func test_searchQuery_trash() {
        let stat = LabelStat(id: "TRASH", name: "Trash", messageCount: 200, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "in:trash")
    }

    func test_searchQuery_spam() {
        let stat = LabelStat(id: "SPAM", name: "Spam", messageCount: 30, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "in:spam")
    }

    func test_searchQuery_starred() {
        let stat = LabelStat(id: "STARRED", name: "Starred", messageCount: 10, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "is:starred")
    }

    func test_searchQuery_promotions() {
        let stat = LabelStat(id: "CATEGORY_PROMOTIONS", name: "Promotions", messageCount: 500, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "category:promotions")
    }

    func test_searchQuery_social() {
        let stat = LabelStat(id: "CATEGORY_SOCIAL", name: "Social", messageCount: 80, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "category:social")
    }

    // MARK: - searchQuery (user labels)

    func test_searchQuery_userLabel_usesLabelName() {
        let stat = LabelStat(id: "Label_12345", name: "Work", messageCount: 20, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "label:Work")
    }

    func test_searchQuery_userLabel_withSpaces() {
        let stat = LabelStat(id: "Label_99", name: "My Projects", messageCount: 5, totalBytes: 0)
        XCTAssertEqual(stat.searchQuery, "label:My Projects")
    }
}
