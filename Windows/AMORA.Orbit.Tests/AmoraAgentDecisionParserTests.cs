using System;
using System.Collections.Generic;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public class AmoraAgentDecisionParserTests
{
    [Fact]
    public void Parse_EmptyOrWhitespace_ThrowsException()
    {
        Assert.Throws<AmoraAgentDecisionException>(() => AmoraAgentDecisionParser.Parse(""));
        Assert.Throws<AmoraAgentDecisionException>(() => AmoraAgentDecisionParser.Parse("   \t\n "));
    }

    [Fact]
    public void Parse_PureProse_ReturnsFinalAnswer()
    {
        var decision = AmoraAgentDecisionParser.Parse("Hello! How can I help you today?");
        var finalAnswer = Assert.IsType<AmoraAgentDecision.FinalAnswer>(decision);
        Assert.Equal("Hello! How can I help you today?", finalAnswer.Text);
    }

    [Fact]
    public void Parse_JsonFinalAnswer_InCodeFence_ReturnsFinalAnswer()
    {
        string raw = "```json\n{\n  \"action\": \"final_answer\",\n  \"answer\": \"The weather is sunny.\"\n}\n```";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var finalAnswer = Assert.IsType<AmoraAgentDecision.FinalAnswer>(decision);
        Assert.Equal("The weather is sunny.", finalAnswer.Text);
    }

    [Fact]
    public void Parse_JsonBareObject_WithAnswer_ReturnsFinalAnswer()
    {
        string raw = "{\n  \"answer\": \"Everything is up to date.\"\n}";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var finalAnswer = Assert.IsType<AmoraAgentDecision.FinalAnswer>(decision);
        Assert.Equal("Everything is up to date.", finalAnswer.Text);
    }

    [Fact]
    public void Parse_JsonToolCall_StandardFormat_ReturnsToolCall()
    {
        string raw = "```json\n{\n  \"action\": \"tool_call\",\n  \"tool\": \"timer.start\",\n  \"params\": {\n    \"duration\": \"15m\",\n    \"label\": \"Work\"\n  }\n}\n```";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolCall = Assert.IsType<AmoraAgentDecision.ToolCall>(decision);
        Assert.Equal("timer.start", toolCall.Tool);
        Assert.Equal("15m", toolCall.Arguments["duration"]);
        Assert.Equal("Work", toolCall.Arguments["label"]);
    }

    [Fact]
    public void Parse_JsonToolCall_DirectFormat_ReturnsToolCall()
    {
        string raw = "{\n  \"tool\": \"battery.status\"\n}";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolCall = Assert.IsType<AmoraAgentDecision.ToolCall>(decision);
        Assert.Equal("battery.status", toolCall.Tool);
        Assert.Empty(toolCall.Arguments);
    }

    [Fact]
    public void Parse_JsonToolBatch_Array_ReturnsToolBatch()
    {
        string raw = "[\n  {\"tool\": \"battery.status\"},\n  {\"tool\": \"timer.status\"}\n]";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolBatch = Assert.IsType<AmoraAgentDecision.ToolBatch>(decision);
        Assert.Equal(2, toolBatch.Calls.Count);
        Assert.Equal("battery.status", toolBatch.Calls[0].Tool);
        Assert.Equal("timer.status", toolBatch.Calls[1].Tool);
    }

    [Fact]
    public void Parse_JsonToolBatch_Object_ReturnsToolBatch()
    {
        string raw = "{\n  \"action\": \"tool_batch\",\n  \"tools\": [\n    {\"tool\": \"media.status\"},\n    {\"tool\": \"battery.status\"}\n  ]\n}";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolBatch = Assert.IsType<AmoraAgentDecision.ToolBatch>(decision);
        Assert.Equal(2, toolBatch.Calls.Count);
        Assert.Equal("media.status", toolBatch.Calls[0].Tool);
        Assert.Equal("battery.status", toolBatch.Calls[1].Tool);
    }

    [Fact]
    public void Parse_LegacyCommandTag_ParsesToToolCall()
    {
        string raw = "Starting that for you. [COMMAND: timer 25m Focus]";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolCall = Assert.IsType<AmoraAgentDecision.ToolCall>(decision);
        Assert.Equal("create_timer", toolCall.Tool);
        Assert.Equal("25", toolCall.Arguments["minutes"]);
    }

    [Fact]
    public void Parse_MalformedJsonInCodeFence_ThrowsAmoraAgentDecisionException()
    {
        string raw = "```json\n{\n  \"action\": \"tool_call\",\n  \"tool\": \"timer.start\",\n  \"params\": {\n    \"duration\":\n```";
        Assert.Throws<AmoraAgentDecisionException>(() => AmoraAgentDecisionParser.Parse(raw));
    }

    [Fact]
    public void Parse_BrokenBracesWithoutValidJson_ThrowsAmoraAgentDecisionException()
    {
        string raw = "I think you should use: { action: invalid_json, tool: broken }";
        Assert.Throws<AmoraAgentDecisionException>(() => AmoraAgentDecisionParser.Parse(raw));
    }

    [Fact]
    public void Parse_JsonMissingToolName_ThrowsAmoraAgentDecisionException()
    {
        string raw = "{\n  \"action\": \"tool_call\",\n  \"params\": {}\n}";
        Assert.Throws<AmoraAgentDecisionException>(() => AmoraAgentDecisionParser.Parse(raw));
    }

    [Fact]
    public void Parse_SafeParameterCoercion_ConvertsNonStringPrimitiveValuesToStrings()
    {
        string raw = "{\n  \"tool\": \"timer.start\",\n  \"params\": {\n    \"duration\": 15,\n    \"active\": true\n  }\n}";
        var decision = AmoraAgentDecisionParser.Parse(raw);
        var toolCall = Assert.IsType<AmoraAgentDecision.ToolCall>(decision);
        Assert.Equal("timer.start", toolCall.Tool);
        Assert.Equal("15", toolCall.Arguments["duration"]);
        Assert.Equal("true", toolCall.Arguments["active"]);
    }
}
