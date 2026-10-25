using AMORA.Orbit.Models;
using Xunit;

namespace AMORA.Orbit.Tests;

public class MascotExpressionTests
{
    [Fact]
    public void FactoryMethods_CreateExpectedMoods()
    {
        var idle = MascotExpression.Idle();
        Assert.Equal(MascotMood.Idle, idle.Mood);
        Assert.Equal(EyeShape.Circle, idle.Eye);
        Assert.Equal(MouthShape.GentleSmile, idle.Mouth);

        var focused = MascotExpression.Focused();
        Assert.Equal(MascotMood.Focused, focused.Mood);
        Assert.Equal(EyeShape.Narrowed, focused.Eye);

        var happy = MascotExpression.Happy();
        Assert.Equal(MascotMood.Happy, happy.Mood);
        Assert.Equal(EyeShape.HappyArcs, happy.Eye);
        Assert.Equal(MouthShape.BigSmile, happy.Mouth);

        var thinking = MascotExpression.Thinking();
        Assert.Equal(MascotMood.Thinking, thinking.Mood);

        var alert = MascotExpression.Alert();
        Assert.Equal(MascotMood.Alert, alert.Mood);
        Assert.Equal(EyeShape.Wide, alert.Eye);
    }
}
