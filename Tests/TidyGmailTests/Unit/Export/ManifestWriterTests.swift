import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Manifest writer for export archives
//
// Generates manifest.json with message IDs, MBOX file checksums, and export metadata.

final class ManifestWriterTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_731_607_200)

    // MARK: - Scenario: manifest contains all required fields

    func test_givenMessageIDsAndMBOXFiles_whenWritten_thenManifestContainsAllFields() throws {
        let mboxData = Data("test mbox content".utf8)
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1", "msg-2"],
            mboxFiles: ["INBOX.mbox": mboxData],
            exportDate: fixedDate
        )

        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        XCTAssertEqual(manifest.version, "1.0")
        XCTAssertEqual(manifest.messageCount, 2)
        XCTAssertEqual(manifest.messageIDs, ["msg-1", "msg-2"]) // sorted
        XCTAssertFalse(manifest.exportDate.isEmpty)
        XCTAssertEqual(manifest.mboxChecksums.count, 1)
        XCTAssertNotNil(manifest.mboxChecksums["INBOX.mbox"])
    }

    // MARK: - Scenario: message IDs are sorted in the manifest

    func test_givenUnsortedMessageIDs_whenWritten_thenIDsAreSorted() throws {
        let manifestData = ManifestWriter.write(
            messageIDs: ["c", "a", "b"],
            mboxFiles: [:],
            exportDate: fixedDate
        )

        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(manifest.messageIDs, ["a", "b", "c"])
    }

    // MARK: - Scenario: checksums are SHA-256 hex strings

    func test_givenMBOXData_whenWritten_thenChecksumIsSHA256Hex() throws {
        let data = Data("hello".utf8)
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1"],
            mboxFiles: ["test.mbox": data],
            exportDate: fixedDate
        )

        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        let checksum = manifest.mboxChecksums["test.mbox"]!

        // SHA-256 hex is 64 characters
        XCTAssertEqual(checksum.count, 64)
        // Known SHA-256 of "hello"
        XCTAssertEqual(checksum, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    // MARK: - Scenario: verification succeeds with matching checksums

    func test_givenCorrectData_whenVerified_thenReturnsTrue() throws {
        let data = Data("test content".utf8)
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1"],
            mboxFiles: ["INBOX.mbox": data],
            exportDate: fixedDate
        )
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        let isValid = ManifestWriter.verify(manifest: manifest, mboxFiles: ["INBOX.mbox": data])
        XCTAssertTrue(isValid)
    }

    // MARK: - Scenario: verification fails with tampered data

    func test_givenTamperedData_whenVerified_thenReturnsFalse() throws {
        let originalData = Data("original".utf8)
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1"],
            mboxFiles: ["INBOX.mbox": originalData],
            exportDate: fixedDate
        )
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        let tamperedData = Data("tampered".utf8)
        let isValid = ManifestWriter.verify(manifest: manifest, mboxFiles: ["INBOX.mbox": tamperedData])
        XCTAssertFalse(isValid)
    }

    // MARK: - Scenario: verification fails with missing file

    func test_givenMissingFile_whenVerified_thenReturnsFalse() throws {
        let data = Data("test".utf8)
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1"],
            mboxFiles: ["INBOX.mbox": data],
            exportDate: fixedDate
        )
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        let isValid = ManifestWriter.verify(manifest: manifest, mboxFiles: [:])
        XCTAssertFalse(isValid)
    }

    // MARK: - Scenario: export date is ISO 8601

    func test_givenDate_whenWritten_thenExportDateIsISO8601() throws {
        let manifestData = ManifestWriter.write(
            messageIDs: [],
            mboxFiles: [:],
            exportDate: fixedDate
        )
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        // ISO 8601 format check
        XCTAssertTrue(manifest.exportDate.contains("T"))
        XCTAssertTrue(manifest.exportDate.contains("Z") || manifest.exportDate.contains("+"))
    }

    // MARK: - Scenario: output is valid pretty-printed JSON

    func test_givenManifest_whenWritten_thenOutputIsValidPrettyJSON() throws {
        let manifestData = ManifestWriter.write(
            messageIDs: ["msg-1"],
            mboxFiles: ["test.mbox": Data("data".utf8)],
            exportDate: fixedDate
        )
        let jsonString = String(data: manifestData, encoding: .utf8)!

        // Pretty-printed JSON contains newlines
        XCTAssertTrue(jsonString.contains("\n"))

        // Verify round-trip
        let decoded = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
        XCTAssertEqual(decoded.messageCount, 1)
    }
}
