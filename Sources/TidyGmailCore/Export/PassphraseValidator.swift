import Foundation

// MARK: - Passphrase strength

public enum PassphraseStrength: Int, Sendable, Comparable {
    case weak = 0
    case fair = 1
    case strong = 2
    case excellent = 3

    public static func < (lhs: PassphraseStrength, rhs: PassphraseStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        }
    }
}

// MARK: - Validation result

public struct PassphraseValidation: Sendable, Equatable {
    public let isValid: Bool
    public let strength: PassphraseStrength
    public let message: String?

    public init(isValid: Bool, strength: PassphraseStrength, message: String?) {
        self.isValid = isValid
        self.strength = strength
        self.message = message
    }
}

// MARK: - Validator

public enum PassphraseValidator {
    public static let minimumLength = 12

    public static func validate(_ passphrase: String) -> PassphraseValidation {
        guard passphrase.count >= minimumLength else {
            return PassphraseValidation(
                isValid: false,
                strength: .weak,
                message: "Passphrase must be at least \(minimumLength) characters."
            )
        }

        let strength = assessStrength(passphrase)
        return PassphraseValidation(isValid: true, strength: strength, message: nil)
    }

    private static func assessStrength(_ passphrase: String) -> PassphraseStrength {
        var categories = 0
        if passphrase.rangeOfCharacter(from: .lowercaseLetters) != nil { categories += 1 }
        if passphrase.rangeOfCharacter(from: .uppercaseLetters) != nil { categories += 1 }
        if passphrase.rangeOfCharacter(from: .decimalDigits) != nil { categories += 1 }
        let symbols = CharacterSet.alphanumerics.inverted
        if passphrase.unicodeScalars.contains(where: { symbols.contains($0) }) { categories += 1 }

        switch categories {
        case 1: return .weak
        case 2: return .fair
        case 3: return .strong
        default: return .excellent
        }
    }
}
