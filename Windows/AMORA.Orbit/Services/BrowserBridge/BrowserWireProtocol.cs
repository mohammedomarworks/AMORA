using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace AMORA.Orbit.Services.BrowserBridge;

/// <summary>The same bounded, allowlisted protocol is used at both local IPC boundaries.</summary>
public static class BrowserWireProtocol
{
    public const string HostName = "com.amora.browser";
    public const string ExtensionId = "pcjbhandogggbhkjdfpcngenaaediend";
    public const string ExtensionOrigin = "chrome-extension://" + ExtensionId + "/";
    public const int MaximumMessageBytes = 65_536;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    public static string CurrentUserPipeName
    {
        get
        {
            using var identity = WindowsIdentity.GetCurrent();
            var sid = identity.User?.Value ?? throw new InvalidOperationException("Windows user identity unavailable.");
            return "AMORA.BrowserMedia." + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sid)))[..24];
        }
    }

    public static async Task<string?> ReadAsync(Stream stream, CancellationToken token = default)
    {
        var header = new byte[4];
        var count = await stream.ReadAsync(header.AsMemory(0, 1), token).ConfigureAwait(false);
        if (count == 0) return null;
        await stream.ReadExactlyAsync(header.AsMemory(1), token).ConfigureAwait(false);
        var length = BinaryPrimitives.ReadUInt32LittleEndian(header);
        if (length == 0 || length > MaximumMessageBytes) throw new InvalidDataException("Invalid browser message size.");
        var body = new byte[(int)length];
        await stream.ReadExactlyAsync(body, token).ConfigureAwait(false);
        return StrictUtf8.GetString(body);
    }

    public static async Task WriteAsync(Stream stream, string message, CancellationToken token = default)
    {
        var body = StrictUtf8.GetBytes(message);
        if (body.Length == 0 || body.Length > MaximumMessageBytes) throw new InvalidDataException("Invalid browser message size.");
        var header = new byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)body.Length);
        await stream.WriteAsync(header, token).ConfigureAwait(false);
        await stream.WriteAsync(body, token).ConfigureAwait(false);
        await stream.FlushAsync(token).ConfigureAwait(false);
    }

    public static bool IsYouTubeUrl(string? value)
    {
        if (value is null || value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort) return false;
        if (uri.Host.Equals("youtu.be", StringComparison.OrdinalIgnoreCase)) return uri.AbsolutePath.Length > 1;
        return (uri.Host.Equals("youtube.com", StringComparison.OrdinalIgnoreCase) || uri.Host.Equals("www.youtube.com", StringComparison.OrdinalIgnoreCase)) &&
            (uri.AbsolutePath == "/watch" || uri.AbsolutePath.StartsWith("/shorts/", StringComparison.Ordinal));
    }

    public static JsonDocument Parse(string json) => JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 16 });
    public static string? Text(JsonElement value, string name, int max = 1000) =>
        value.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.String && item.GetString() is { } text && text.Length <= max ? text : null;
    public static bool TryBool(JsonElement value, string name, out bool result)
    {
        result = false;
        if (!value.TryGetProperty(name, out var item) || item.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        result = item.GetBoolean(); return true;
    }
    public static int? Integer(JsonElement value, string name) => value.TryGetProperty(name, out var item) && item.TryGetInt32(out var number) ? number : null;
    private static double Seconds(JsonElement value, string name) => value.TryGetProperty(name, out var item) && item.TryGetDouble(out var number) && double.IsFinite(number) && number >= 0 && number <= 31_536_000 ? number : 0;

    /// <summary>Drop unknown fields and unsupported actions; never forward general page content.</summary>
    public static string? NormalizeBrowserMessage(string json)
    {
        try
        {
            using var doc = Parse(json);
            var value = doc.RootElement;
            if (value.ValueKind != JsonValueKind.Object) return null;
            switch (Text(value, "type", 32))
            {
                case "hello": return "{\"type\":\"hello\"}";
                case "ping": return "{\"type\":\"ping\"}";
                case "clear": return "{\"type\":\"clear\"}";
                case "mediaState": return NormalizeState(value);
                case "mediaCommandResult":
                    var request = Text(value, "requestId", 64);
                    var action = Text(value, "action", 16)?.ToLowerInvariant();
                    var provider = Text(value, "provider", 32)?.ToLowerInvariant();
                    var tab = Integer(value, "tabId") ?? Integer(value, "targetTabId");
                    if (!Guid.TryParse(request, out _) || action is not ("play" or "pause") || provider is not (null or "youtube") ||
                        !TryBool(value, "success", out var success) || success && tab is not >= 0) return null;
                    string? state = value.TryGetProperty("state", out var rawState) && rawState.ValueKind == JsonValueKind.Object ? NormalizeState(rawState) : null;
                    return JsonSerializer.Serialize(new { type = "mediaCommandResult", requestId = request, action, tabId = tab, success,
                        reason = SafeReason(Text(value, "reason", 100)), state = state == null ? (JsonElement?)null : JsonSerializer.Deserialize<JsonElement>(state) });
                case "contentPong":
                    if (!Guid.TryParse(Text(value, "requestId", 64), out _) || !TryBool(value, "success", out var pongSuccess) || !TryBool(value, "hasVideo", out var hasVideo)) return null;
                    return JsonSerializer.Serialize(new { type = "contentPong", requestId = Text(value, "requestId", 64), success = pongSuccess, hasVideo });
                default: return null;
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException) { return null; }
    }

    private static string? NormalizeState(JsonElement value)
    {
        var url = Text(value, "url", 2048);
        var tab = Integer(value, "tabId");
        var window = Integer(value, "windowId");
        if (Text(value, "provider", 32) != "YouTube" || Text(value, "browser", 32) != "Chrome" || !IsYouTubeUrl(url) ||
            tab is not >= 0 || window is not >= 0 || !TryBool(value, "isPlaying", out var playing) ||
            !TryBool(value, "hasVideo", out var hasVideo) || !hasVideo || !TryBool(value, "contentScriptReady", out var ready)) return null;
        return JsonSerializer.Serialize(new { type = "mediaState", provider = "YouTube", browser = "Chrome", url, tabId = tab, windowId = window,
            title = Text(value, "title") ?? "", channel = Text(value, "channel", 500) ?? "", isPlaying = playing,
            currentTime = Seconds(value, "currentTime"), duration = Seconds(value, "duration"), hasVideo = true, contentScriptReady = ready,
            capabilities = new { play = ready, pause = ready, next = false, previous = false, seek = false } });
    }

    public static string? NormalizeAppCommand(string json)
    {
        try
        {
            using var doc = Parse(json); var value = doc.RootElement;
            if (value.ValueKind != JsonValueKind.Object || !Guid.TryParse(Text(value, "requestId", 64), out var request)) return null;
            if (Text(value, "type", 32) == "contentPing") return JsonSerializer.Serialize(new { type = "contentPing", requestId = request.ToString() });
            var action = Text(value, "action", 16);
            var tab = Integer(value, "tabId");
            if (Text(value, "type", 32) != "mediaCommand" || Text(value, "provider", 32) != "youtube" || action is not ("play" or "pause") || tab is not >= 0) return null;
            return JsonSerializer.Serialize(new { type = "mediaCommand", provider = "youtube", action, tabId = tab, requestId = request.ToString() });
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException) { return null; }
    }

    private static string? SafeReason(string? reason) => reason != null && reason.All(c => char.IsAsciiLetterOrDigit(c) || c == '_') ? reason : null;
}
