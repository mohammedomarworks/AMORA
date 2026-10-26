using System.Text.RegularExpressions;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Explicit local grammar derived from AmoraMemoryCommandParser.swift.</summary>
public static class MemoryCommandParser
{
    private static readonly string[] ClearPhrases = ["forget everything you remember", "forget everything", "forget all", "forget all memories", "forget all my memories", "clear all memories", "clear my memories", "clear all my memories", "clear memories", "delete all memories", "delete all my memories", "erase all memories", "wipe all memories", "wipe memories", "reset memories"];
    private static readonly string[] ConfirmPhrases = ["yes forget everything", "yes forget all", "yes forget all memories", "yes clear all memories", "yes clear memories", "confirm clear memories", "confirm forget everything", "yes please forget everything", "yes delete all memories"];
    private static readonly string[] ListPhrases = ["what do you remember about me", "what do you remember", "what memories do you have", "what are my memories", "what are your memories", "show memories", "show my memories", "list memories", "list my memories", "my memories", "view memories", "view my memories", "tell me what you remember", "tell me what you remember about me"];

    public static MemoryCommand? Parse(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        string text = input.Trim().Replace('’', '\'');
        for (int i = 0; i < 3; i++)
        {
            string? prefix = new[] { "please ", "hey amora, ", "amora, ", "can you please ", "could you please " }
                .FirstOrDefault(p => text.StartsWith(p, StringComparison.OrdinalIgnoreCase));
            if (prefix == null) break;
            text = text[prefix.Length..].Trim();
        }
        text = text.TrimEnd('.', '!', '?').Trim();
        string normalized = Normalize(text);
        if (ConfirmPhrases.Contains(normalized)) return new(MemoryCommandKind.ConfirmClear);
        if (ClearPhrases.Contains(normalized)) return new(MemoryCommandKind.RequestClear);
        if (ListPhrases.Contains(normalized)) return new(MemoryCommandKind.List);
        var recall = Remainder(text, ["what do you remember about ", "what do you remember regarding ", "what do you recall about ", "what memories do you have about ", "tell me what you remember about ", "search memory for ", "search memories for ", "search memory about ", "search memories about ", "recall memory about ", "recall memory for ", "recall memories about ", "recall memories for ", "recall "]);
        if (recall != null) return new(MemoryCommandKind.Recall, CleanSubject(recall));

        var save = Remainder(text, ["remember that ", "remember: ", "remember:", "remember ", "don't forget that ", "dont forget that ", "don't forget ", "dont forget ", "save memory: ", "save memory that ", "save memory ", "save to memory: ", "save to memory that ", "save to memory ", "store in memory that ", "store in memory ", "keep in mind that "]);
        if (save != null)
        {
            if (save.Length > 1500 || save.Length == 0) return new(MemoryCommandKind.Invalid);
            var pair = SplitFact(save);
            return new(MemoryCommandKind.Save, pair.Key, pair.Value);
        }
        var forget = Remainder(text, ["forget my preference for ", "forget my preferences for ", "forget about ", "forget that ", "forget: ", "forget:", "forget ", "delete memory about ", "delete memory that ", "delete memory ", "remove memory about ", "remove memory that ", "remove memory "]);
        if (forget != null) return new(MemoryCommandKind.Forget, CleanSubject(forget));

        // Preserve actual device commands for the assistant's existing router.
        if (!Regex.IsMatch(text, @"\b(timer|alarm|volume|brightness|track|song)\b", RegexOptions.IgnoreCase))
        {
            var update = Remainder(text, ["change my memory about ", "change my memory that ", "change my memory ", "change memory about ", "change memory that ", "change memory ", "update my memory about ", "update my memory that ", "update my memory ", "update memory about ", "update memory that ", "update memory ", "change my ", "update my ", "switch my ", "modify my ", "change preference for ", "update preference for "]);
            if (update != null)
            {
                var match = Regex.Match(update, @"^(.+?)(?:\s+to\s+|\s*=\s*|:\s*)(.+)$", RegexOptions.IgnoreCase);
                if (!match.Success) return new(MemoryCommandKind.Invalid);
                return new(MemoryCommandKind.Update, CleanSubject(match.Groups[1].Value), match.Groups[2].Value.Trim());
            }
        }
        if (normalized is "remember" or "save memory" or "save to memory" or "recall" or "forget" or "delete memory" or "remove memory")
            return new(MemoryCommandKind.Invalid);
        return null;
    }

    public static string Normalize(string text) => Regex.Replace(text.ToLowerInvariant(), @"[^\p{L}\p{N}]+", " ").Trim();

    public static string CleanSubject(string text)
    {
        text = text.Trim();
        foreach (string prefix in new[] { "my ", "the ", "our ", "preference for ", "preferences for " })
            if (text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) text = text[prefix.Length..].Trim();
        return text;
    }

    private static string? Remainder(string text, string[] prefixes)
    {
        foreach (string prefix in prefixes)
            if (text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return text[prefix.Length..].Trim();
        return null;
    }

    private static (string Key, string Value) SplitFact(string body)
    {
        var pair = Regex.Match(body, @"^(.+?)(?:\s*=\s*|:\s+)(.+)$");
        if (pair.Success) return (CleanSubject(pair.Groups[1].Value), pair.Groups[2].Value.Trim());
        string lower = body.ToLowerInvariant();
        if (lower.Contains(" prefer ") || lower.StartsWith("prefer "))
        {
            foreach (var category in new[] {
                (Key: "music preference", Terms: new[] { "youtube", "spotify", "apple music", "music", "song" }),
                (Key: "theme preference", Terms: new[] { "dark mode", "light mode", "theme" }),
                (Key: "editor preference", Terms: new[] { "vscode", "vs code", "xcode", "cursor", "sublime", "editor" }),
                (Key: "browser preference", Terms: new[] { "chrome", "safari", "firefox", "browser" }) })
                if (category.Terms.Any(lower.Contains)) return (category.Key, body);
            return ("preference: " + Regex.Replace(body, @"^.*?\bprefer\s+", "", RegexOptions.IgnoreCase), body);
        }
        if (lower.Contains("working on ") || lower.Contains("project is ")) return ("programming project", body);
        pair = Regex.Match(body, @"^(.+?)\s+is\s+(.+)$", RegexOptions.IgnoreCase);
        if (pair.Success) return (CleanSubject(pair.Groups[1].Value), pair.Groups[2].Value.Trim());
        return (CleanSubject(body), body);
    }
}
