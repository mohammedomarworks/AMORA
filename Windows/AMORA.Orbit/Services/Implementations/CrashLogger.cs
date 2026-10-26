using System;
using System.IO;
using System.Reflection;
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

    private static readonly Regex AuthorizationHeaderRegex = new(
        @"(?i)\b(authorization)\s*[:=]\s*['""]?(?:bearer\s+)?[^'""\s,;}]+",
        RegexOptions.Compiled);

    private static string _startupStage = "process-startup";

    public static string LogFilePath
    {
        get
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData)) localAppData = Path.GetTempPath();
            return Path.Combine(localAppData, "AMORA", "Logs", "crash.log");
        }
    }

    public static void SetStartupStage(string stage)
    {
        if (!string.IsNullOrWhiteSpace(stage)) _startupStage = SanitizeMessage(stage);
    }

    public static void LogException(Exception? ex, string? customLogDirectory = null, string? startupStage = null)
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
                logDir = Path.GetDirectoryName(LogFilePath)!;
            }

            Directory.CreateDirectory(logDir);
            string logPath = Path.Combine(logDir, "crash.log");

            var sb = new StringBuilder();
            sb.AppendLine("================================================================================");
            sb.AppendLine($"Timestamp: {DateTimeOffset.UtcNow:O}");
            var assembly = typeof(CrashLogger).Assembly;
            var version = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                ?? assembly.GetName().Version?.ToString()
                ?? "unknown";
            sb.AppendLine($"Application: AMORA Orbit (v{SanitizeMessage(version)}, {(Environment.Is64BitProcess ? "x64" : "x86")})");
            sb.AppendLine($"OperatingSystem: {Environment.OSVersion}");
            sb.AppendLine($"StartupStage: {SanitizeMessage(startupStage ?? _startupStage)}");
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

        // HTTP exception messages can include an authorization header value.
        sanitized = AuthorizationHeaderRegex.Replace(sanitized, "$1: [REDACTED]");

        // 2. Redact common credential patterns (password, secret, bearer, key, token)
        sanitized = SensitiveTokenRegex.Replace(sanitized, "$1: [REDACTED]");

        return sanitized;
    }
}
