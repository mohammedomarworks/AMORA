using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class ConversationSessionTests
{
    [Fact]
    public void AddTurn_RecordsAlternatingUserAndModelMessages()
    {
        var session = new ConversationSession(defaultMaxTurns: 4);

        session.AddTurn("What is the speed of light?", "Approximately 299,792 km/s.");

        Assert.Equal(1, session.TurnCount);
        var history = session.GetHistory();
        Assert.Equal(2, history.Count);

        Assert.Equal(ChatRole.User, history[0].Role);
        Assert.Equal("user", history[0].RoleString);
        Assert.Equal("What is the speed of light?", history[0].Content);

        Assert.Equal(ChatRole.Model, history[1].Role);
        Assert.Equal("model", history[1].RoleString);
        Assert.Equal("Approximately 299,792 km/s.", history[1].Content);
    }

    [Fact]
    public void AddTurn_TrimsOldestTurns_WhenLimitExceeded()
    {
        // Limit to 2 turns (4 messages maximum)
        var session = new ConversationSession(defaultMaxTurns: 2);

        session.AddTurn("Turn 1 Question", "Turn 1 Answer");
        session.AddTurn("Turn 2 Question", "Turn 2 Answer");
        session.AddTurn("Turn 3 Question", "Turn 3 Answer");

        Assert.Equal(2, session.TurnCount);
        var history = session.GetHistory();
        Assert.Equal(4, history.Count);

        // Turn 1 should be trimmed out, leaving Turn 2 and Turn 3
        Assert.Equal("Turn 2 Question", history[0].Content);
        Assert.Equal(ChatRole.User, history[0].Role);
        Assert.Equal("Turn 2 Answer", history[1].Content);
        Assert.Equal(ChatRole.Model, history[1].Role);

        Assert.Equal("Turn 3 Question", history[2].Content);
        Assert.Equal(ChatRole.User, history[2].Role);
        Assert.Equal("Turn 3 Answer", history[3].Content);
        Assert.Equal(ChatRole.Model, history[3].Role);
    }

    [Fact]
    public void AddTurn_AlwaysEnsuresHistoryStartsWithUserTurn()
    {
        var session = new ConversationSession(defaultMaxTurns: 1);

        session.AddTurn("First user message", "First model message");
        session.AddTurn("Second user message", "Second model message");

        Assert.Equal(1, session.TurnCount);
        var history = session.GetHistory();
        Assert.Equal(2, history.Count);

        Assert.Equal(ChatRole.User, history[0].Role);
        Assert.Equal("Second user message", history[0].Content);
        Assert.Equal(ChatRole.Model, history[1].Role);
        Assert.Equal("Second model message", history[1].Content);
    }

    [Theory]
    [InlineData(null, "Response")]
    [InlineData("", "Response")]
    [InlineData("   ", "Response")]
    [InlineData("Question", null)]
    [InlineData("Question", "")]
    [InlineData("Question", "   ")]
    public void AddTurn_IgnoresNullOrWhitespaceInput(string? user, string? model)
    {
        var session = new ConversationSession(defaultMaxTurns: 3);

        session.AddTurn(user!, model!);

        Assert.Equal(0, session.TurnCount);
        Assert.Empty(session.GetHistory());
    }

    [Fact]
    public void Clear_ResetsAllMessagesAndTurnCount()
    {
        var session = new ConversationSession(defaultMaxTurns: 5);
        session.AddTurn("Q1", "A1");
        session.AddTurn("Q2", "A2");

        Assert.Equal(2, session.TurnCount);
        Assert.NotEmpty(session.GetHistory());

        session.Clear();

        Assert.Equal(0, session.TurnCount);
        Assert.Empty(session.GetHistory());
    }

    [Fact]
    public void MaxTurns_DynamicallyTrimsExistingExcess()
    {
        var session = new ConversationSession(defaultMaxTurns: 5);
        session.AddTurn("Q1", "A1");
        session.AddTurn("Q2", "A2");
        session.AddTurn("Q3", "A3");
        session.AddTurn("Q4", "A4");

        Assert.Equal(4, session.TurnCount);

        // Reduce limit dynamically to 2 turns
        session.MaxTurns = 2;

        Assert.Equal(2, session.TurnCount);
        var history = session.GetHistory();
        Assert.Equal(4, history.Count);
        Assert.Equal("Q3", history[0].Content);
        Assert.Equal(ChatRole.User, history[0].Role);
    }

    [Fact]
    public void ThreadSafety_ConcurrentAddAndRead_DoesNotThrow()
    {
        var session = new ConversationSession(defaultMaxTurns: 5);

        Parallel.For(0, 100, i =>
        {
            session.AddTurn($"Question {i}", $"Answer {i}");
            var snapshot = session.GetHistory();
            Assert.True(snapshot.Count <= 10);
            if (snapshot.Count > 0)
            {
                Assert.Equal(ChatRole.User, snapshot[0].Role);
            }
        });

        Assert.True(session.TurnCount <= 5);
    }
}
