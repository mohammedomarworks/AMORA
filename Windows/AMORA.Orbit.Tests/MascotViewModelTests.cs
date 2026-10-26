using AMORA.Orbit.Models;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class MascotViewModelTests
{
    [Theory]
    [InlineData(MascotMood.Curious)]
    [InlineData(MascotMood.Grumpy)]
    [InlineData(MascotMood.Affection)]
    [InlineData(MascotMood.Celebrating)]
    public void SetMood_PreservesRealExpression(MascotMood mood)
    {
        var vm = new RobotMascotViewModel();
        vm.SetMood(mood, "Event description");
        Assert.Equal(mood, vm.Mood);
        Assert.Equal(MascotExpression.Create(mood).EyeShape, vm.Expression.EyeShape);
        Assert.Equal("Event description", vm.StatusSubtext);
    }

    [Fact]
    public async Task ClickReaction_DoesNotOverwriteNewerThinkingEvent()
    {
        var vm = new RobotMascotViewModel();
        var reaction = vm.TriggerClickReactionAsync();
        Assert.Equal(MascotMood.Affection, vm.Mood);
        vm.SetMood(MascotMood.Thinking);
        await reaction;
        Assert.Equal(MascotMood.Thinking, vm.Mood);
    }
}
