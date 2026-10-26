using System.Text.RegularExpressions;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Matches the Mac memory boundary; no capture or credential persistence.</summary>
public static class MemoryPrivacyValidator
{
    public const int MaximumItems = 250;
    public const int MaximumKeyLength = 120;
    public const int MaximumValueLength = 1000;

    private static readonly string[] RestrictedPhrases =
    [
        "password", "passwd", "passcode", "pin code", "pincode", "api key", "apikey", "secret key", "private key",
        "auth token", "bearer token", "access token", "refresh token", "session token", "ssh key", "credentials",
        "credit card", "debit card", "card number", "cvv", "cvc", "bank account", "routing number", "iban", "social security", "ssn",
        "medical record", "health record", "prescription", "diagnosis", "blood pressure", "blood sugar", "insulin", "medication dose",
        "doctor's note", "doctor note", "therapy note", "health condition", "medical condition", "symptoms",
        "private message", "direct message", "chat log", "email contents", "inbox message",
        "clipboard content", "clipboard history", "file content", "contents of file", "screen content", "screenshot content", "keystroke", "keylogger"
    ];
    private static readonly Regex SecretPattern = new(
        @"\b(?:sk-[A-Za-z0-9_-]{15,}|ghp_[A-Za-z0-9_-]{15,}|github_pat_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,}|\d{3}-\d{2}-\d{4})\b|\b(?:\d[ -]?){13,19}\b|-----BEGIN .*PRIVATE KEY-----",
        RegexOptions.Compiled | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));

    public static string? Validate(string? key, string? value)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(value)) return "A memory needs both a subject and a value.";
        if (key.Length > MaximumKeyLength || value.Length > MaximumValueLength)
            return $"Keep memory subjects within {MaximumKeyLength} characters and values within {MaximumValueLength} characters.";
        string combined = $"{key} {value}".Replace('’', '\'');
        if (combined.Any(c => char.IsControl(c) && c is not '\r' and not '\n' and not '\t'))
            return "Memory cannot contain control characters.";
        if (RestrictedPhrases.Any(phrase => combined.Contains(phrase, StringComparison.OrdinalIgnoreCase)) || SecretPattern.IsMatch(combined))
            return "I can't save credentials, financial or health data, private messages, or captured contents to memory.";
        return null;
    }
}
