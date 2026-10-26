using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Executes only explicit user memory requests. No cloud dependency, automatic
/// harvesting, conversation injection, or AI-accessible mutation tools.
/// </summary>
public sealed class ExplicitMemoryService : IExplicitMemoryService
{
    public const string ClearActionId = "clear_memories";
    private readonly IMemoryStorage _storage;
    private readonly Func<bool> _isEnabled;
    private readonly Func<DateTimeOffset> _clock;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private ExplicitMemory[]? _items;
    private string? _recoveryNotice;
    private PendingClear? _pendingClear;
    private sealed record PendingClear(DateTimeOffset ExpiresAt);
    public bool HasPendingClear => _pendingClear is { } pending && pending.ExpiresAt > _clock();

    public ExplicitMemoryService(IMemoryStorage? storage = null, Func<bool>? isEnabled = null, Func<DateTimeOffset>? clock = null)
    {
        _storage = storage ?? new DpapiMemoryStorage();
        _isEnabled = isEnabled ?? (() => true); // Mac Preferences.memoryEnabled default.
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    public async Task<AssistantExecutionResult?> TryExecuteAsync(string input, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            MemoryCommand? command = MemoryCommandParser.Parse(input);
            if (command?.Kind != MemoryCommandKind.ConfirmClear) CancelPendingClear();
            if (command == null) return null;
            if (!_isEnabled()) { CancelPendingClear(); return AssistantExecutionResult.Failed("Memory is turned off in Settings."); }
            if (command.Kind == MemoryCommandKind.Invalid)
                return AssistantExecutionResult.Failed("Use an explicit memory command, for example: remember my editor is VS Code.");
            if (command.Subject.Length > 1500 || command.Value.Length > MemoryPrivacyValidator.MaximumValueLength)
                return AssistantExecutionResult.Failed("That memory command is too long.");
            await EnsureLoadedAsync(cancellationToken);
            AssistantExecutionResult result = command.Kind switch
            {
                MemoryCommandKind.Save => await SaveAsync(command.Subject, command.Value, cancellationToken),
                MemoryCommandKind.Update => await UpdateAsync(command.Subject, command.Value, cancellationToken),
                MemoryCommandKind.Forget => await ForgetAsync(command.Subject, cancellationToken),
                MemoryCommandKind.List => Describe(_items!),
                MemoryCommandKind.Recall => Describe(FindMatches(command.Subject, exactFirst: false)),
                MemoryCommandKind.RequestClear => RequestClear(),
                MemoryCommandKind.ConfirmClear => await ClearConfirmedCoreAsync(cancellationToken),
                _ => AssistantExecutionResult.Failed("That memory command is not supported.")
            };
            if (_recoveryNotice != null)
            {
                result = result with { Message = _recoveryNotice + " " + result.Message };
                _recoveryNotice = null;
            }
            return result;
        }
        catch (OperationCanceledException) { throw; }
        catch { return AssistantExecutionResult.Failed("Memory could not be read or saved safely. Existing memories were preserved; try again after restarting AMORA."); }
        finally { _gate.Release(); }
    }

    public async Task<AssistantExecutionResult> ConfirmClearAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!_isEnabled()) { CancelPendingClear(); return AssistantExecutionResult.Failed("Memory is turned off in Settings."); }
            await EnsureLoadedAsync(cancellationToken);
            return await ClearConfirmedCoreAsync(cancellationToken);
        }
        catch (OperationCanceledException) { throw; }
        catch { return AssistantExecutionResult.Failed("Memory could not be cleared safely. Existing memories were preserved."); }
        finally { _gate.Release(); }
    }

    public void CancelPendingClear() => Interlocked.Exchange(ref _pendingClear, null);

    public async Task<IReadOnlyList<ExplicitMemory>> GetRelevantMemoriesAsync(string query, int limit = 3, CancellationToken cancellationToken = default)
    {
        if (!_isEnabled() || string.IsNullOrWhiteSpace(query) || limit <= 0) return Array.Empty<ExplicitMemory>();
        await _gate.WaitAsync(cancellationToken);
        try
        {
            await EnsureLoadedAsync(cancellationToken);
            if (_items == null || _items.Length == 0) return Array.Empty<ExplicitMemory>();
            return RankRelevantMemories(query, _items, limit);
        }
        catch (OperationCanceledException) { throw; }
        catch
        {
            return Array.Empty<ExplicitMemory>();
        }
        finally
        {
            _gate.Release();
        }
    }

    public static IReadOnlyList<ExplicitMemory> RankRelevantMemories(string query, IReadOnlyList<ExplicitMemory> items, int limit = 3)
    {
        if (items.Count == 0 || string.IsNullOrWhiteSpace(query) || limit <= 0) return Array.Empty<ExplicitMemory>();

        string normalizedQuery = MemoryCommandParser.Normalize(query);
        if (string.IsNullOrWhiteSpace(normalizedQuery)) return Array.Empty<ExplicitMemory>();

        var queryTokens = normalizedQuery.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (queryTokens.Count == 0) return Array.Empty<ExplicitMemory>();
        var queryStems = queryTokens.Select(Stem).ToHashSet(StringComparer.OrdinalIgnoreCase);

        var scored = new List<(ExplicitMemory Item, int Score)>();
        foreach (var item in items)
        {
            string normKey = MemoryCommandParser.Normalize(item.Key);
            string normVal = MemoryCommandParser.Normalize(item.Value);
            int score = 0;

            // Exact phrase match in key
            if (normKey.Equals(normalizedQuery, StringComparison.OrdinalIgnoreCase))
                score += 25;
            else if (normKey.Contains(normalizedQuery, StringComparison.OrdinalIgnoreCase) || normalizedQuery.Contains(normKey, StringComparison.OrdinalIgnoreCase))
                score += 12;

            // Exact phrase match in value
            if (normVal.Contains(normalizedQuery, StringComparison.OrdinalIgnoreCase))
                score += 10;

            var keyTokens = normKey.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var valTokens = normVal.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var keyStems = keyTokens.Select(Stem).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var valStems = valTokens.Select(Stem).ToHashSet(StringComparer.OrdinalIgnoreCase);

            // Token overlap
            score += queryTokens.Intersect(keyTokens, StringComparer.OrdinalIgnoreCase).Count() * 6;
            score += queryTokens.Intersect(valTokens, StringComparer.OrdinalIgnoreCase).Count() * 3;

            // Stem overlap
            score += queryStems.Intersect(keyStems, StringComparer.OrdinalIgnoreCase).Count() * 4;
            score += queryStems.Intersect(valStems, StringComparer.OrdinalIgnoreCase).Count() * 2;

            // Semantic domain associations
            if (queryStems.Any(s => s is "music" or "song" or "track"))
            {
                if (normKey.Contains("spotify", StringComparison.OrdinalIgnoreCase) || normVal.Contains("spotify", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("youtube", StringComparison.OrdinalIgnoreCase) || normVal.Contains("youtube", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("apple music", StringComparison.OrdinalIgnoreCase) || normVal.Contains("apple music", StringComparison.OrdinalIgnoreCase))
                {
                    score += 6;
                }
            }
            if (queryStems.Any(s => s is "prefer" or "favorit"))
            {
                if (normKey.Contains("prefer", StringComparison.OrdinalIgnoreCase) || normVal.Contains("prefer", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("favorit", StringComparison.OrdinalIgnoreCase) || normVal.Contains("favorit", StringComparison.OrdinalIgnoreCase))
                {
                    score += 8;
                }
            }
            if (queryStems.Any(s => s is "program" or "code" or "project" or "develop" or "ide" or "editor"))
            {
                if (normKey.Contains("project", StringComparison.OrdinalIgnoreCase) || normVal.Contains("project", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("amora", StringComparison.OrdinalIgnoreCase) || normVal.Contains("amora", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("code", StringComparison.OrdinalIgnoreCase) || normVal.Contains("code", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("editor", StringComparison.OrdinalIgnoreCase) || normVal.Contains("editor", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("vs code", StringComparison.OrdinalIgnoreCase) || normVal.Contains("vs code", StringComparison.OrdinalIgnoreCase) ||
                    normKey.Contains("visual studio", StringComparison.OrdinalIgnoreCase) || normVal.Contains("visual studio", StringComparison.OrdinalIgnoreCase))
                {
                    score += 6;
                }
            }

            if (score > 0)
            {
                scored.Add((item, score));
            }
        }

        return scored
            .OrderByDescending(x => x.Score)
            .ThenByDescending(x => x.Item.UpdatedAt)
            .Take(limit)
            .Select(x => x.Item)
            .ToArray();
    }

    public static string Stem(string word)
    {
        string w = word.Trim().ToLowerInvariant();
        if (w.Length <= 3) return w;
        if (w.EndsWith("sses", StringComparison.Ordinal)) return w[..^2];
        if (w.EndsWith("ies", StringComparison.Ordinal)) return w[..^3] + "y";
        if (w.EndsWith("ing", StringComparison.Ordinal) && w.Length > 5) return w[..^3];
        if (w.EndsWith("tion", StringComparison.Ordinal) && w.Length > 5) return w[..^4];
        if (w.EndsWith("ment", StringComparison.Ordinal) && w.Length > 5) return w[..^4];
        if (w.EndsWith("ed", StringComparison.Ordinal) && w.Length > 4) return w[..^2];
        if (w.EndsWith("ly", StringComparison.Ordinal) && w.Length > 4) return w[..^2];
        if (w.EndsWith("es", StringComparison.Ordinal) && w.Length > 4) return w[..^2];
        if (w.EndsWith("s", StringComparison.Ordinal) && !w.EndsWith("ss", StringComparison.Ordinal) && w.Length > 3) return w[..^1];
        return w;
    }

    private async Task EnsureLoadedAsync(CancellationToken token)
    {
        if (_items != null) return;
        var loaded = await _storage.LoadAsync(token);
        _items = loaded.Items.ToArray();
        _recoveryNotice = loaded.RecoveryNotice;
    }

    private async Task<AssistantExecutionResult> SaveAsync(string key, string value, CancellationToken token)
    {
        key = key.Trim(); value = value.Trim();
        string? rejection = MemoryPrivacyValidator.Validate(key, value);
        if (rejection != null) return AssistantExecutionResult.Failed(rejection);
        var matching = _items!.Where(item => KeysEquivalent(item.Key, key)).ToArray();
        if (matching.Length > 1) return Ambiguous();
        var existing = matching.SingleOrDefault();
        if (existing == null && _items!.Length >= MemoryPrivacyValidator.MaximumItems)
            return AssistantExecutionResult.Failed($"Memory is full ({MemoryPrivacyValidator.MaximumItems} facts). Forget a fact before saving another.");
        var now = _clock();
        var item = existing == null ? new ExplicitMemory(Guid.NewGuid(), key, value, now, now) :
            existing with { Key = key, Value = value, UpdatedAt = now < existing.CreatedAt ? existing.CreatedAt : now };
        var next = new[] { item }.Concat(_items!.Where(m => m.Id != item.Id)).ToArray();
        await CommitAsync(next, token);
        return AssistantExecutionResult.Success($"Remembered {item.Key}: {item.Value}");
    }

    private async Task<AssistantExecutionResult> UpdateAsync(string subject, string value, CancellationToken token)
    {
        var matches = FindMatches(subject);
        if (matches.Length > 1) return Ambiguous();
        if (matches.Length == 0) return AssistantExecutionResult.Failed("I couldn't find a saved memory matching that subject.");
        var item = matches[0];
        string? rejection = MemoryPrivacyValidator.Validate(item.Key, value);
        if (rejection != null) return AssistantExecutionResult.Failed(rejection);
        var now = _clock();
        var updated = item with { Value = value.Trim(), UpdatedAt = now < item.CreatedAt ? item.CreatedAt : now };
        await CommitAsync(_items!.Select(m => m.Id == item.Id ? updated : m).ToArray(), token);
        return AssistantExecutionResult.Success($"Updated {updated.Key}: {updated.Value}");
    }

    private async Task<AssistantExecutionResult> ForgetAsync(string subject, CancellationToken token)
    {
        var matches = FindMatches(subject);
        if (matches.Length > 1) return Ambiguous();
        if (matches.Length == 0) return AssistantExecutionResult.Failed("I don't have a memory matching that subject. Use its full subject or exact value.");
        var item = matches[0];
        await CommitAsync(_items!.Where(m => m.Id != item.Id).ToArray(), token);
        return AssistantExecutionResult.Success($"Forgotten: {item.Key}.");
    }

    private AssistantExecutionResult RequestClear()
    {
        if (_items!.Length == 0) return AssistantExecutionResult.Information("No saved memories to clear.");
        _pendingClear = new PendingClear(_clock().AddMinutes(2));
        return AssistantExecutionResult.NeedsConfirmation(
            $"Forget all {_items.Length} saved memories? This cannot be undone. Confirm or cancel.", ClearActionId);
    }

    private async Task<AssistantExecutionResult> ClearConfirmedCoreAsync(CancellationToken token)
    {
        var pending = Interlocked.Exchange(ref _pendingClear, null);
        if (pending == null || pending.ExpiresAt <= _clock())
            return AssistantExecutionResult.Failed("There is no current request to clear memories. Ask to clear all memories first.");
        await CommitAsync(Array.Empty<ExplicitMemory>(), token);
        return AssistantExecutionResult.Success("All saved memories have been forgotten.");
    }

    private async Task CommitAsync(ExplicitMemory[] next, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        await _storage.SaveAsync(next, token);
        _items = next; // Publish only after persistence succeeds; no cache rollback race.
    }

    private ExplicitMemory[] FindMatches(string subject, bool exactFirst = true)
    {
        string normalized = MemoryCommandParser.Normalize(MemoryCommandParser.CleanSubject(subject));
        if (string.IsNullOrWhiteSpace(normalized)) return [];
        var exact = _items!.Where(i => MemoryCommandParser.Normalize(i.Key) == normalized || MemoryCommandParser.Normalize(i.Value) == normalized).ToArray();
        if (exactFirst && exact.Length > 0) return exact;
        var significant = SignificantTokens(normalized);
        if (exactFirst && significant.Count == 0) return [];
        return _items!.Where(i =>
        {
            string key = MemoryCommandParser.Normalize(i.Key);
            string value = MemoryCommandParser.Normalize(i.Value);
            var itemTokens = SignificantTokens(key + " " + value);
            return key.Contains(normalized, StringComparison.Ordinal) || value.Contains(normalized, StringComparison.Ordinal) ||
                significant.Count > 0 && significant.IsSubsetOf(itemTokens) ||
                (!exactFirst && (normalized is "preference" or "preferences") && key.Contains("preference", StringComparison.Ordinal));
        }).ToArray();
    }

    private static bool KeysEquivalent(string first, string second)
    {
        if (MemoryCommandParser.Normalize(first) == MemoryCommandParser.Normalize(second)) return true;
        var left = SignificantTokens(first);
        return left.Count > 0 && left.SetEquals(SignificantTokens(second));
    }

    private static HashSet<string> SignificantTokens(string text) => MemoryCommandParser.Normalize(text).Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Where(token => token is not ("my" or "the" or "our" or "i" or "a" or "an" or "is" or "that" or "for" or "preference" or "preferences" or "favorite" or "favourite"))
        .ToHashSet(StringComparer.Ordinal);

    private static AssistantExecutionResult Ambiguous() => AssistantExecutionResult.Failed("That matches more than one memory. Nothing changed; use the full subject or exact value.");

    private static AssistantExecutionResult Describe(IReadOnlyList<ExplicitMemory> items) =>
        AssistantExecutionResult.Information(items.Count == 0 ? "No saved memories match that request." :
            string.Join(Environment.NewLine, items.Select(i => $"• {i.Key}: {i.Value}")));
}
