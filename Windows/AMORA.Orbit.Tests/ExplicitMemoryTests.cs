using System.Text;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class ExplicitMemoryTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "AMORA_ExplicitMemory_" + Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task ExplicitLifecycle_SaveRecallUpdateListForget_UsesOneStore()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        Assert.Equal(AssistantResultStatus.Success, (await memory.TryExecuteAsync("Remember that I prefer YouTube over Apple Music."))!.Status);
        Assert.Contains("YouTube", (await memory.TryExecuteAsync("What do you remember about my preferences?"))!.Message);
        Assert.Equal(AssistantResultStatus.Success, (await memory.TryExecuteAsync("Change my music preference to Spotify."))!.Status);
        Assert.Single(storage.Items);
        Assert.Equal("Spotify", storage.Items.Single().Value);
        Assert.Contains("Spotify", (await memory.TryExecuteAsync("List my memories."))!.Message);
        Assert.Equal(AssistantResultStatus.Success, (await memory.TryExecuteAsync("Forget my preference for Spotify."))!.Status);
        Assert.Empty(storage.Items);
    }

    [Theory]
    [InlineData("I remember that I prefer YouTube")]
    [InlineData("I can't remember my password")]
    [InlineData("Can you remember anything?")]
    [InlineData("Could you remember this for me if I ask later?")]
    [InlineData("I use Spotify every day")]
    [InlineData("Delete note 1 from my notes folder")]
    [InlineData("Delete file test.txt")]
    [InlineData("I change clothes every day")]
    [InlineData("Can you update me on the news?")]
    public async Task StatementsAndUnrelatedActions_NeverWriteMemory(string input)
    {
        var storage = new TestStorage();
        Assert.Null(await new ExplicitMemoryService(storage).TryExecuteAsync(input));
        Assert.Equal(0, storage.SaveCalls);
        Assert.Equal(0, storage.LoadCalls);
    }

    [Theory]
    [InlineData("Please remember that my dog's name is Milo")]
    [InlineData("Hey Amora, remember my favorite drink is iced matcha")]
    [InlineData("Don't forget that my timezone is EST")]
    [InlineData("Save to memory: my car is a Honda Civic")]
    [InlineData("Store in memory that I use Dvorak layout")]
    [InlineData("Keep in mind that I am vegetarian")]
    [InlineData("remember: favorite language is Swift")]
    public void ExplicitMacImperatives_ParseAsSave(string input) =>
        Assert.Equal(MemoryCommandKind.Save, MemoryCommandParser.Parse(input)!.Kind);

    [Theory]
    [InlineData("password", "value")]
    [InlineData("api key", "secret-value")]
    [InlineData("auth", "sk-abcdefghijklmnopqrstuvwxyz123456")]
    [InlineData("auth", "ghp_abcdefghijklmnopqrstuvwxyz")]
    [InlineData("auth", "github_pat_abcdefghijklmnopqrstuvwxyz")]
    [InlineData("auth", "AIzaSy1234567890abcdefghijklmnopqrstuvwxyz")]
    [InlineData("auth", "eyJabcdefghijklmnopqrstuvwxyz123456")]
    [InlineData("card", "4111 1111 1111 1111")]
    [InlineData("identity", "123-45-6789")]
    [InlineData("health", "medical condition")]
    [InlineData("record", "my prescription")]
    [InlineData("private message", "hello")]
    [InlineData("clipboard contents", "hello")]
    [InlineData("file contents", "hello")]
    [InlineData("screen contents", "hello")]
    [InlineData("keystrokes", "hello")]
    public async Task PrivacyRejectsSensitiveValues_WithoutEchoOrPersistence(string key, string value)
    {
        var storage = new TestStorage();
        var result = await new ExplicitMemoryService(storage).TryExecuteAsync($"remember {key}: {value}");
        Assert.Equal(AssistantResultStatus.Failed, result!.Status);
        Assert.Equal(0, storage.SaveCalls);
        Assert.DoesNotContain(value, result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task DisabledMemory_DoesNotLoadSaveRecallOrClear()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage, () => false);
        foreach (string input in new[] { "remember editor: VS Code", "list memories", "recall editor", "forget editor", "clear all memories" })
            Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync(input))!.Status);
        Assert.Equal(0, storage.LoadCalls);
        Assert.Equal(0, storage.SaveCalls);
        Assert.False(memory.HasPendingClear);
    }

    [Fact]
    public async Task SaveEquivalentSubject_UpdatesExistingIdentity()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        await memory.TryExecuteAsync("remember favorite music: jazz");
        var original = storage.Items.Single();
        await memory.TryExecuteAsync("remember music preference: classical");
        var updated = Assert.Single(storage.Items);
        Assert.Equal(original.Id, updated.Id);
        Assert.Equal(original.CreatedAt, updated.CreatedAt);
        Assert.Equal("classical", updated.Value);
    }

    [Fact]
    public async Task AmbiguousForgetAndUpdate_ChangeNothing_ExactTargetLeavesOtherFavorites()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        await memory.TryExecuteAsync("remember favorite music: jazz");
        await memory.TryExecuteAsync("remember favorite food: pizza");
        await memory.TryExecuteAsync("remember favorite color: blue");
        Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync("forget favorite"))!.Status);
        Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync("change my favorite to green"))!.Status);
        Assert.Equal(3, storage.Items.Count);
        Assert.Equal(AssistantResultStatus.Success, (await memory.TryExecuteAsync("forget favorite music"))!.Status);
        Assert.Equal(2, storage.Items.Count);
        Assert.DoesNotContain(storage.Items, item => item.Key == "favorite music");
    }

    [Fact]
    public async Task ClearAll_RequiresPendingUnexpiredConfirmation_AndCanBeCancelled()
    {
        var now = DateTimeOffset.UtcNow;
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage, clock: () => now);
        await memory.TryExecuteAsync("remember editor: VS Code");
        Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync("yes clear all memories"))!.Status);
        Assert.Single(storage.Items);
        Assert.Equal(AssistantResultStatus.NeedsConfirmation, (await memory.TryExecuteAsync("clear all memories"))!.Status);
        Assert.True(memory.HasPendingClear);
        Assert.Single(storage.Items);
        memory.CancelPendingClear();
        Assert.Equal(AssistantResultStatus.Failed, (await memory.ConfirmClearAsync()).Status);
        await memory.TryExecuteAsync("clear all memories");
        now = now.AddMinutes(3);
        Assert.Equal(AssistantResultStatus.Failed, (await memory.ConfirmClearAsync()).Status);
        Assert.Single(storage.Items);
        await memory.TryExecuteAsync("clear all memories");
        Assert.Equal(AssistantResultStatus.Success, (await memory.ConfirmClearAsync()).Status);
        Assert.Empty(storage.Items);
        Assert.False(memory.HasPendingClear);
    }

    [Fact]
    public async Task NewInput_InvalidatesPendingClear()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        await memory.TryExecuteAsync("remember drink: tea");
        await memory.TryExecuteAsync("forget everything");
        Assert.Null(await memory.TryExecuteAsync("start a timer"));
        Assert.False(memory.HasPendingClear);
        Assert.Equal(AssistantResultStatus.Failed, (await memory.ConfirmClearAsync()).Status);
        Assert.Single(storage.Items);
    }

    [Fact]
    public async Task FailedWrites_PreserveCacheAndDisk_ForEveryMutation()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        await memory.TryExecuteAsync("remember drink: tea");
        storage.FailSave = true;
        foreach (string input in new[] { "remember editor: Vim", "change my drink to coffee", "forget drink" })
        {
            Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync(input))!.Status);
            Assert.Equal("tea", Assert.Single(storage.Items).Value);
            Assert.Contains("drink: tea", (await memory.TryExecuteAsync("list memories"))!.Message);
        }
        await memory.TryExecuteAsync("clear all memories");
        Assert.Equal(AssistantResultStatus.Failed, (await memory.ConfirmClearAsync()).Status);
        Assert.Contains("drink: tea", (await memory.TryExecuteAsync("list memories"))!.Message);
        Assert.Single(storage.Items);
    }

    [Fact]
    public async Task FailedLoad_DoesNotOverwriteUnreadableStorage()
    {
        var storage = new TestStorage { FailLoad = true };
        var result = await new ExplicitMemoryService(storage).TryExecuteAsync("remember editor: Vim");
        Assert.Equal(AssistantResultStatus.Failed, result!.Status);
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task Cancellation_PreventsWrite()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => memory.TryExecuteAsync("remember editor: Vim", cts.Token));
        Assert.Equal(0, storage.SaveCalls);
    }

    [Fact]
    public async Task ConcurrentCommands_AreSerializedWithoutLosingFacts()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        await Task.WhenAll(Enumerable.Range(0, 30).Select(i => memory.TryExecuteAsync($"remember project {i}: value {i}")));
        Assert.Equal(30, storage.Items.Count);
        Assert.Equal(30, storage.Items.Select(i => i.Id).Distinct().Count());
    }

    [Fact]
    public async Task Bounds_RejectOversizedFactsAndStoreOverflow()
    {
        var storage = new TestStorage();
        var memory = new ExplicitMemoryService(storage);
        Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync("remember subject: " + new string('x', 1001)))!.Status);
        for (int i = 0; i < MemoryPrivacyValidator.MaximumItems; i++) await memory.TryExecuteAsync($"remember item {i}: value {i}");
        Assert.Equal(AssistantResultStatus.Failed, (await memory.TryExecuteAsync("remember another: value"))!.Status);
        Assert.Equal(MemoryPrivacyValidator.MaximumItems, storage.Items.Count);
    }

    [Fact]
    public async Task DpapiPersistence_IsEncryptedAndSurvivesReload()
    {
        string path = Path.Combine(_directory, "memory.enc");
        var first = new ExplicitMemoryService(new DpapiMemoryStorage(path));
        Assert.Equal(AssistantResultStatus.Success, (await first.TryExecuteAsync("remember favorite city: Kyoto"))!.Status);
        Assert.DoesNotContain("Kyoto", Encoding.UTF8.GetString(await File.ReadAllBytesAsync(path)));
        var second = new ExplicitMemoryService(new DpapiMemoryStorage(path));
        Assert.Contains("favorite city: Kyoto", (await second.TryExecuteAsync("list memories"))!.Message);
    }

    [Fact]
    public async Task CorruptCiphertext_IsPreservedBeforeRecoveryAndNewSave()
    {
        Directory.CreateDirectory(_directory);
        string path = Path.Combine(_directory, "memory.enc");
        byte[] corrupt = [1, 2, 3, 4, 5];
        await File.WriteAllBytesAsync(path, corrupt);
        var memory = new ExplicitMemoryService(new DpapiMemoryStorage(path));
        Assert.Contains("preserved", (await memory.TryExecuteAsync("list memories"))!.Message);
        string backup = Assert.Single(Directory.GetFiles(_directory, "memory.enc.corrupt-*"));
        Assert.Equal(corrupt, await File.ReadAllBytesAsync(backup));
        Assert.Equal(AssistantResultStatus.Success, (await memory.TryExecuteAsync("remember editor: Vim"))!.Status);
        Assert.Equal(corrupt, await File.ReadAllBytesAsync(backup));
        Assert.Contains("Vim", (await new ExplicitMemoryService(new DpapiMemoryStorage(path)).TryExecuteAsync("list memories"))!.Message);
    }

    [Fact]
    public async Task SecondWriter_CannotOverwriteNewerPersistedMemory()
    {
        string path = Path.Combine(_directory, "memory.enc");
        var first = new ExplicitMemoryService(new DpapiMemoryStorage(path));
        var stale = new ExplicitMemoryService(new DpapiMemoryStorage(path));
        await first.TryExecuteAsync("list memories");
        await stale.TryExecuteAsync("list memories");
        await first.TryExecuteAsync("remember editor: Vim");
        Assert.Equal(AssistantResultStatus.Failed, (await stale.TryExecuteAsync("remember drink: tea"))!.Status);
        var result = await new ExplicitMemoryService(new DpapiMemoryStorage(path)).TryExecuteAsync("list memories");
        Assert.Contains("editor: Vim", result!.Message);
        Assert.DoesNotContain("drink: tea", result.Message);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }

    private sealed class TestStorage : IMemoryStorage
    {
        public IReadOnlyList<ExplicitMemory> Items { get; private set; } = Array.Empty<ExplicitMemory>();
        public bool FailSave { get; set; }
        public bool FailLoad { get; set; }
        public int SaveCalls { get; private set; }
        public int LoadCalls { get; private set; }
        public Task<MemoryLoadResult> LoadAsync(CancellationToken cancellationToken = default)
        {
            LoadCalls++;
            if (FailLoad) throw new IOException("simulated read or quarantine failure");
            return Task.FromResult(new MemoryLoadResult(Items.ToArray()));
        }
        public Task SaveAsync(IReadOnlyList<ExplicitMemory> items, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            SaveCalls++;
            if (FailSave) throw new IOException("simulated write failure containing private-data-that-must-not-be-echoed");
            Items = items.ToArray();
            return Task.CompletedTask;
        }
    }
}
