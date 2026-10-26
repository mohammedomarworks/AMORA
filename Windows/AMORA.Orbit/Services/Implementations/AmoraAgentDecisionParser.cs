using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.RegularExpressions;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Strictly parses and validates model responses into typed <see cref="AmoraAgentDecision"/>s.
/// Validates JSON structure, decision types, and tool parameters while rejecting malformed or unsupported output.
/// </summary>
public static class AmoraAgentDecisionParser
{
    private static readonly Regex CommandTagRegex = new(
        @"\[(?:COMMAND|ACTION):\s*([^\]]+)\]",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static AmoraAgentDecision Parse(string rawText)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            throw new AmoraAgentDecisionException("The model returned an empty response.");
        }

        string trimmed = rawText.Trim();

        // 1. Attempt to extract and parse JSON object or array candidates
        var jsonCandidates = ExtractJsonCandidates(trimmed);
        foreach (var candidate in jsonCandidates)
        {
            try
            {
                using var document = JsonDocument.Parse(candidate);
                return ParseJsonElement(document.RootElement);
            }
            catch (JsonException)
            {
                // Continue to next candidate
            }
        }

        // 2. Check for legacy command tag (e.g. [COMMAND: start 12m timer])
        var commandMatch = CommandTagRegex.Match(trimmed);
        if (commandMatch.Success)
        {
            string proposedCommand = commandMatch.Groups[1].Value.Trim();
            string cleanText = CommandTagRegex.Replace(trimmed, "").Trim();
            var (toolName, toolArgs) = MapCommandStringToTool(proposedCommand);
            if (!string.IsNullOrEmpty(toolName))
            {
                return new AmoraAgentDecision.ToolCall(toolName, toolArgs);
            }
            if (!string.IsNullOrEmpty(cleanText))
            {
                return new AmoraAgentDecision.FinalAnswer(cleanText);
            }
        }

        // 3. If model output contains markdown code fences or curly braces indicating a failed/malformed JSON attempt, reject it safely
        if (trimmed.Contains("```") || trimmed.Contains('{') || trimmed.Contains('}'))
        {
            throw new AmoraAgentDecisionException("Malformed or unparseable JSON structure in model output.");
        }

        // 4. Pure conversational prose (no JSON attempt) is treated as a final answer
        return new AmoraAgentDecision.FinalAnswer(trimmed);
    }

    private static IEnumerable<string> ExtractJsonCandidates(string text)
    {
        var list = new List<string>();

        // Code fence: ```json ... ``` or ``` ... ```
        int fenceStart = text.IndexOf("```json", StringComparison.OrdinalIgnoreCase);
        if (fenceStart >= 0)
        {
            int contentStart = fenceStart + 7;
            int fenceEnd = text.IndexOf("```", contentStart, StringComparison.Ordinal);
            if (fenceEnd > contentStart)
            {
                list.Add(text[contentStart..fenceEnd].Trim());
            }
        }

        int genericFenceStart = text.IndexOf("```", StringComparison.Ordinal);
        if (genericFenceStart >= 0 && genericFenceStart != fenceStart)
        {
            int contentStart = genericFenceStart + 3;
            int fenceEnd = text.IndexOf("```", contentStart, StringComparison.Ordinal);
            if (fenceEnd > contentStart)
            {
                list.Add(text[contentStart..fenceEnd].Trim());
            }
        }

        // Braced JSON: { ... }
        int firstBrace = text.IndexOf('{');
        int lastBrace = text.LastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            list.Add(text.Substring(firstBrace, lastBrace - firstBrace + 1).Trim());
        }

        // Bracketed JSON: [ ... ]
        int firstBracket = text.IndexOf('[');
        int lastBracket = text.LastIndexOf(']');
        if (firstBracket >= 0 && lastBracket > firstBracket)
        {
            list.Add(text.Substring(firstBracket, lastBracket - firstBracket + 1).Trim());
        }

        list.Add(text);
        return list;
    }

    private static AmoraAgentDecision ParseJsonElement(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array)
        {
            var batch = new List<AmoraAgentDecision.ToolCall>();
            foreach (var element in root.EnumerateArray())
            {
                if (element.ValueKind == JsonValueKind.Object)
                {
                    if (TryParseToolCallFromObject(element, out var call))
                    {
                        batch.Add(call);
                    }
                }
            }

            if (batch.Count == 1) return batch[0];
            if (batch.Count > 1) return new AmoraAgentDecision.ToolBatch(batch);
            throw new AmoraAgentDecisionException("Array contained no valid tool calls.");
        }

        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new AmoraAgentDecisionException("Expected JSON object or array for agent decision.");
        }

        // A. Check for "type", "decision", or action keyword
        string? rawType = GetPropertyString(root, "type") ?? GetPropertyString(root, "decision");
        if (string.IsNullOrWhiteSpace(rawType) && root.TryGetProperty("action", out var actElem) && actElem.ValueKind == JsonValueKind.String)
        {
            string actVal = actElem.GetString()?.Trim().ToLowerInvariant() ?? "";
            if (actVal is "final_answer" or "finalanswer" or "tool_call" or "toolcall" or "tool_batch" or "toolbatch")
            {
                rawType = actVal;
            }
        }

        if (!string.IsNullOrWhiteSpace(rawType))
        {
            string normalizedType = rawType.Trim().ToLowerInvariant();
            switch (normalizedType)
            {
                case "final_answer":
                case "finalanswer":
                case "answer":
                case "response":
                case "message":
                    string answer = GetPropertyString(root, "answer")
                        ?? GetPropertyString(root, "response")
                        ?? GetPropertyString(root, "message")
                        ?? GetPropertyString(root, "text")
                        ?? string.Empty;
                    return new AmoraAgentDecision.FinalAnswer(answer.Trim());

                case "tool_call":
                case "toolcall":
                case "call":
                    string? callToolName = GetPropertyString(root, "tool") ?? GetPropertyString(root, "name");
                    if (string.IsNullOrWhiteSpace(callToolName) && root.TryGetProperty("action", out var actP) && actP.ValueKind == JsonValueKind.String)
                    {
                        string a = actP.GetString()?.Trim() ?? "";
                        if (a != "tool_call" && a != "toolcall") callToolName = a;
                    }
                    if (string.IsNullOrWhiteSpace(callToolName))
                    {
                        throw new AmoraAgentDecisionException("Tool call missing tool name or valid parameters.");
                    }
                    if (!TryParseToolCallFromObject(root, out var call))
                    {
                        throw new AmoraAgentDecisionException("Tool call missing tool name or valid parameters.");
                    }
                    return call;

                case "tool_batch":
                case "toolbatch":
                case "batch":
                    var batchList = new List<AmoraAgentDecision.ToolCall>();
                    if (root.TryGetProperty("tools", out var tProp) && tProp.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var elem in tProp.EnumerateArray())
                        {
                            if (TryParseToolCallFromObject(elem, out var bCall)) batchList.Add(bCall);
                        }
                    }
                    else if (root.TryGetProperty("actions", out var aPropBatch) && aPropBatch.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var elem in aPropBatch.EnumerateArray())
                        {
                            if (TryParseToolCallFromObject(elem, out var bCall)) batchList.Add(bCall);
                        }
                    }
                    if (batchList.Count > 0)
                    {
                        return new AmoraAgentDecision.ToolBatch(batchList);
                    }
                    throw new AmoraAgentDecisionException("Tool batch missing tools array.");

                default:
                    throw new AmoraAgentDecisionException($"Unknown decision type: '{rawType}'.");
            }
        }

        // B. Check for explicit "final_answer" or "answer" property
        string? directAnswer = GetPropertyString(root, "final_answer") ?? GetPropertyString(root, "answer");
        if (directAnswer != null)
        {
            return new AmoraAgentDecision.FinalAnswer(directAnswer.Trim());
        }

        // C. Check for legacy "actions" or "calls" array
        if (root.TryGetProperty("actions", out var actionsProp) && actionsProp.ValueKind == JsonValueKind.Array)
        {
            var batch = new List<AmoraAgentDecision.ToolCall>();
            foreach (var act in actionsProp.EnumerateArray())
            {
                if (TryParseToolCallFromObject(act, out var call)) batch.Add(call);
            }
            if (batch.Count == 1) return batch[0];
            if (batch.Count > 1) return new AmoraAgentDecision.ToolBatch(batch);
        }

        if (root.TryGetProperty("calls", out var callsProp) && callsProp.ValueKind == JsonValueKind.Array)
        {
            var batch = new List<AmoraAgentDecision.ToolCall>();
            foreach (var c in callsProp.EnumerateArray())
            {
                if (TryParseToolCallFromObject(c, out var call)) batch.Add(call);
            }
            if (batch.Count == 1) return batch[0];
            if (batch.Count > 1) return new AmoraAgentDecision.ToolBatch(batch);
        }

        // D. Top-level direct tool schema: {"tool": "name", "arguments": {...}}
        if (TryParseToolCallFromObject(root, out var directCall))
        {
            return directCall;
        }

        throw new AmoraAgentDecisionException("Unrecognized dictionary structure in model output.");
    }

    private static bool TryParseToolCallFromObject(JsonElement element, out AmoraAgentDecision.ToolCall call)
    {
        call = null!;
        string? toolName = GetPropertyString(element, "tool")
            ?? GetPropertyString(element, "name");

        if (string.IsNullOrWhiteSpace(toolName))
        {
            string? actStr = GetPropertyString(element, "action") ?? GetPropertyString(element, "call");
            if (actStr is not ("tool_call" or "final_answer" or "tool_batch"))
            {
                toolName = actStr;
            }
        }

        if (string.IsNullOrWhiteSpace(toolName)) return false;

        var arguments = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        // Arguments may be under "arguments", "parameters", "params", "args"
        if (element.TryGetProperty("arguments", out var argsProp) && argsProp.ValueKind == JsonValueKind.Object)
        {
            ExtractArguments(argsProp, arguments);
        }
        else if (element.TryGetProperty("parameters", out var paramsProp) && paramsProp.ValueKind == JsonValueKind.Object)
        {
            ExtractArguments(paramsProp, arguments);
        }
        else if (element.TryGetProperty("params", out var pProp) && pProp.ValueKind == JsonValueKind.Object)
        {
            ExtractArguments(pProp, arguments);
        }
        else if (element.TryGetProperty("args", out var aProp) && aProp.ValueKind == JsonValueKind.Object)
        {
            ExtractArguments(aProp, arguments);
        }
        else
        {
            // Or flat properties on the element itself (excluding keywords)
            foreach (var prop in element.EnumerateObject())
            {
                string name = prop.Name;
                if (name is "type" or "decision" or "tool" or "action" or "call" or "name") continue;
                arguments[name] = StringifyJsonElement(prop.Value);
            }
        }

        call = new AmoraAgentDecision.ToolCall(toolName.Trim(), arguments);
        return true;
    }

    private static void ExtractArguments(JsonElement container, Dictionary<string, string> target)
    {
        foreach (var prop in container.EnumerateObject())
        {
            target[prop.Name] = StringifyJsonElement(prop.Value);
        }
    }

    private static string StringifyJsonElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.String => element.GetString() ?? string.Empty,
            JsonValueKind.Number => element.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => string.Empty,
            _ => element.GetRawText()
        };
    }

    private static string? GetPropertyString(JsonElement element, string propertyName)
    {
        if (element.TryGetProperty(propertyName, out var prop))
        {
            if (prop.ValueKind == JsonValueKind.String) return prop.GetString();
            if (prop.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) return prop.GetRawText();
        }
        return null;
    }

    private static (string? Tool, IReadOnlyDictionary<string, string> Arguments) MapCommandStringToTool(string command)
    {
        string norm = command.Trim().ToLowerInvariant();
        var args = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        if (norm.Contains("timer"))
        {
            if (norm.Contains("cancel") || norm.Contains("stop"))
            {
                return ("timer.cancel", args);
            }
            if (norm.Contains("pause"))
            {
                return ("timer.pause", args);
            }
            if (norm.Contains("resume"))
            {
                return ("timer.resume", args);
            }
            var minuteMatch = Regex.Match(norm, @"(\d+)\s*(?:m|min|mins|minute|minutes)");
            if (minuteMatch.Success)
            {
                args["minutes"] = minuteMatch.Groups[1].Value;
                return ("create_timer", args);
            }
            var secondMatch = Regex.Match(norm, @"(\d+)\s*(?:s|sec|secs|second|seconds)");
            if (secondMatch.Success)
            {
                args["seconds"] = secondMatch.Groups[1].Value;
                return ("create_timer", args);
            }
            return ("create_timer", args);
        }

        if (norm.Contains("music") || norm.Contains("track") || norm.Contains("media"))
        {
            if (norm.Contains("play")) return ("media.play", args);
            if (norm.Contains("pause")) return ("media.pause", args);
            if (norm.Contains("next")) return ("media.next", args);
            if (norm.Contains("previous") || norm.Contains("back")) return ("media.previous", args);
        }

        if (norm.Contains("battery")) return ("get_battery_status", args);
        if (norm.Contains("system") || norm.Contains("telemetry")) return ("get_system_status", args);
        if (norm.Contains("reset settings") || norm.Contains("restore defaults"))
        {
            args["name"] = "Reset Settings";
            args["prompt"] = "Are you sure you want to reset settings?";
            return ("system.confirm_test", args);
        }

        return (null, args);
    }
}
