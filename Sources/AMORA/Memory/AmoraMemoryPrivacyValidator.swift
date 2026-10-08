import Foundation

/// Result of evaluating a memory candidate against privacy and security rules.
public enum AmoraMemoryPrivacyValidationResult: Equatable, Sendable {
    case allowed
    case rejected(reason: String)
}

/// Validation and redaction layer enforcing AMORA's strict privacy policy.
/// Rejects passwords, API keys, auth tokens, financial secrets, health data,
/// private messages, clipboard contents, file contents, screen contents, or keystrokes.
public struct AmoraMemoryPrivacyValidator: Sendable {
    public static let shared = AmoraMemoryPrivacyValidator()

    public init() {}

    public func validate(key: String, value: String) -> AmoraMemoryPrivacyValidationResult {
        let combined = "\(key) \(value)"
        return validate(text: combined)
    }

    public func validate(text: String) -> AmoraMemoryPrivacyValidationResult {
        let lower = text.lowercased()

        // 1. Passwords, Credentials & Authentication Tokens
        let credentialKeywords = [
            "password", "passwd", "passcode", "pin code", "pincode",
            "api key", "apikey", "secret key", "private key",
            "auth token", "bearer token", "access token", "refresh token",
            "session token", "ssh key", "credentials"
        ]
        if let matched = credentialKeywords.first(where: { lower.contains($0) }) {
            return .rejected(reason: "I can't save sensitive credentials or \(matched)s to protect your privacy.")
        }

        // Token & API Key Regex checks (e.g., OpenAI, GitHub, JWT)
        let tokenPatterns = [
            #"\bsk-[a-zA-Z0-9_-]{15,}\b"#,
            #"\bghp_[a-zA-Z0-9_-]{15,}\b"#,
            #"\bgithub_pat_[a-zA-Z0-9_-]{20,}\b"#,
            #"\beyJ[a-zA-Z0-9_-]{20,}\b"#
        ]
        for pattern in tokenPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return .rejected(reason: "I can't save API keys or authentication tokens to protect your privacy.")
            }
        }

        // 2. Financial Secrets
        let financialKeywords = [
            "credit card", "debit card", "card number", "cvv", "cvc",
            "bank account", "routing number", "iban",
            "social security", "ssn"
        ]
        if let matched = financialKeywords.first(where: { lower.contains($0) }) {
            return .rejected(reason: "I can't save financial secrets or \(matched) information to protect your privacy.")
        }

        // Credit Card Numbers & SSN Regex
        let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b"#
        if text.range(of: ssnPattern, options: .regularExpression) != nil {
            return .rejected(reason: "I can't save Social Security Numbers or government IDs to protect your privacy.")
        }

        let creditCardPattern = #"\b(?:\d[ -]*?){13,19}\b"#
        if let match = text.range(of: creditCardPattern, options: .regularExpression) {
            let digitsOnly = text[match].filter(\.isNumber)
            if digitsOnly.count >= 13 && digitsOnly.count <= 19 {
                return .rejected(reason: "I can't save credit card numbers or payment details to protect your privacy.")
            }
        }

        // 3. Health Data
        let healthKeywords = [
            "medical record", "health record", "prescription", "diagnosis",
            "blood pressure", "blood sugar", "insulin", "medication dose",
            "doctor's note", "doctor note", "therapy note",
            "health condition", "medical condition", "symptoms"
        ]
        if let matched = healthKeywords.first(where: { lower.contains($0) }) {
            return .rejected(reason: "I can't save health data or \(matched) to protect your privacy.")
        }

        // 4. Private Messages & Communications
        let messageKeywords = [
            "private message", "direct message", "chat log", "email contents", "inbox message"
        ]
        if messageKeywords.contains(where: { lower.contains($0) }) {
            return .rejected(reason: "I can't save private messages or communication logs to protect your privacy.")
        }

        // 5. Clipboard, File Contents, Screen Contents, Keystrokes
        let captureKeywords = [
            "clipboard content", "clipboard history",
            "file content", "contents of file", "file contents",
            "screen content", "screenshot content", "screen contents",
            "keystroke", "keylogger", "keystrokes"
        ]
        if let matched = captureKeywords.first(where: { lower.contains($0) }) {
            return .rejected(reason: "I can't save \(matched) to protect your privacy.")
        }

        return .allowed
    }
}
