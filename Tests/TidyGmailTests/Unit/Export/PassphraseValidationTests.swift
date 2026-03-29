import Foundation
import XCTest
@testable import TidyGmailCore

// Feature: Passphrase validation for encrypted export
//
// Validates that passphrases meet minimum security requirements and that
// strength is assessed based on character variety.

final class PassphraseValidationTests: XCTestCase {

    // MARK: - Scenario: passphrase shorter than 12 characters is invalid

    func test_givenShortPassphrase_whenValidated_thenInvalid() {
        let result = PassphraseValidator.validate("short")

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.strength, .weak)
        XCTAssertNotNil(result.message)
        XCTAssertTrue(result.message?.contains("12") == true)
    }

    // MARK: - Scenario: empty passphrase is invalid

    func test_givenEmptyPassphrase_whenValidated_thenInvalid() {
        let result = PassphraseValidator.validate("")

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.strength, .weak)
    }

    // MARK: - Scenario: exactly 12 characters is valid

    func test_givenExactly12Characters_whenValidated_thenValid() {
        let result = PassphraseValidator.validate("abcdefghijkl")

        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.message)
    }

    // MARK: - Scenario: 11 characters is invalid

    func test_given11Characters_whenValidated_thenInvalid() {
        let result = PassphraseValidator.validate("abcdefghijk")

        XCTAssertFalse(result.isValid)
    }

    // MARK: - Scenario: lowercase only is weak strength

    func test_givenLowercaseOnly_whenValidated_thenWeakStrength() {
        let result = PassphraseValidator.validate("abcdefghijklmn")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.strength, .weak)
    }

    // MARK: - Scenario: lowercase + uppercase is fair

    func test_givenMixedCase_whenValidated_thenFairStrength() {
        let result = PassphraseValidator.validate("AbcDefGhiJkl")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.strength, .fair)
    }

    // MARK: - Scenario: lowercase + uppercase + digits is strong

    func test_givenMixedCaseAndDigits_whenValidated_thenStrongStrength() {
        let result = PassphraseValidator.validate("AbcDef123Ghi")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.strength, .strong)
    }

    // MARK: - Scenario: all character types is excellent

    func test_givenAllCharacterTypes_whenValidated_thenExcellentStrength() {
        let result = PassphraseValidator.validate("AbcDef123!@#")

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.strength, .excellent)
    }

    // MARK: - Scenario: minimumLength constant is 12

    func test_minimumLengthIs12() {
        XCTAssertEqual(PassphraseValidator.minimumLength, 12)
    }

    // MARK: - Scenario: strength labels are human-readable

    func test_strengthLabelsAreReadable() {
        XCTAssertEqual(PassphraseStrength.weak.label, "Weak")
        XCTAssertEqual(PassphraseStrength.fair.label, "Fair")
        XCTAssertEqual(PassphraseStrength.strong.label, "Strong")
        XCTAssertEqual(PassphraseStrength.excellent.label, "Excellent")
    }

    // MARK: - Scenario: strengths are comparable

    func test_strengthsAreOrdered() {
        XCTAssertTrue(PassphraseStrength.weak < .fair)
        XCTAssertTrue(PassphraseStrength.fair < .strong)
        XCTAssertTrue(PassphraseStrength.strong < .excellent)
    }
}
