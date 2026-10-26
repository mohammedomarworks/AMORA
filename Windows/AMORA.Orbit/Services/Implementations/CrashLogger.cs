using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Diagnostic crash logger for unhandled exceptions in AMORA Orbit.
/// Automatically redacts API keys, credentials, and sensitive tokens before writing to disk.
/// Logs are saved to %LocalAppData%\AMORA\Logs\crash.log.
/// </summary>
public static class CrashLogger
{
    private static readonly Regex ApiKeyRegex = new(
        @"AIzaSy[A-Za-z0-9_-]{33}",
        RegexOptions.Compiled);

    private static readonly Regex SensitiveTokenRegex = new(
        @"(?i)(password|secret|bearer|key|token)\s*[:=]\s*['""]?([^'"";\s]{4,})",
        RegexOptions.Compiled);

    public static void LogException(Exception? ex, string? customLogDirectory = null)
    {
        if (ex == null) return;

        try
        {
            string logDir;
            if (!string.IsNullOrWhiteSpace(customLogDirectory))
            {
                logDir = customLogDirectory;
            }
            else
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (string.IsNullOrWhiteSpace(localAppData))
                {
                    localAppData = AppContext.BaseDirectory;
                }
                logDir = Path.Combine(localAppData, "AMORA", "Logs");
            }

            Directory.CreateDirectory(logDir);
            string logPath = Path.Combine(logDir, "crash.log");

            var sb = new StringBuilder();
            sb.AppendLine("================================================================================");
            sb.AppendLine($"Timestamp: {DateTimeOffset.UtcNow:O}");
            sb.AppendLine("Application: AMORA Orbit (v0.6.0-beta win-x64)");
            sb.AppendLine($"OperatingSystem: {Environment.OSVersion}");
            sb.AppendLine($"ExceptionType: {ex.GetType().FullName}");
            sb.AppendLine($"Message: {SanitizeMessage(ex.Message)}");
            sb.AppendLine("StackTrace:");
            sb.AppendLine(SanitizeMessage(ex.StackTrace ?? string.Empty));

            if (ex.InnerException != null)
            {
                sb.AppendLine($"InnerException: {ex.InnerException.GetType().FullName}");
                sb.AppendLine($"InnerMessage: {SanitizeMessage(ex.InnerException.Message)}");
            }
            sb.AppendLine("================================================================================");
            sb.AppendLine();

            File.AppendAllText(logPath, sb.ToString(), Encoding.UTF8);
        }
        catch
        {
            // Fail silent: never throw from the unhandled crash logger
        }
    }

    public static string SanitizeMessage(string message)
    {
        if (string.IsNullOrWhiteSpace(message)) return string.Empty;

        // 1. Redact Gemini API keys (AIzaSy...)
        string sanitized = ApiKeyRegex.Replace(message, "AIzaSy*********************************");

        // 2. Redact common credential patterns (password, secret, bearer, key, token)
        sanitized = SensitiveTokenRegex.Replace(sanitized, "$1: [REDACTED]");

        return sanitized;
    }
}
