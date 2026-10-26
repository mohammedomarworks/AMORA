namespace AMORA.Orbit.Models;

/// <summary>States shared by AMORA's event-driven face and accessible description.</summary>
public enum MascotMood
{
    Neutral, Idle, Focused, Happy, Thinking, Curious, Affection, Grumpy,
    Surprised, Listening, Alert, Celebrating, Excited, Music, Bored, Sleepy, Concerned
}

public enum EyeShape
{
    NormalDot, Circle = NormalDot, HappyArch, HappyArcs = HappyArch,
    NarrowLine, Narrowed = NarrowLine, Heart, WideCircle, Wide = WideCircle,
    SlantedGrumpy, BlinkClosed, SadArc, HalfClosed
}

public enum MouthShape
{
    Hidden, NeutralSmall, Smile, GentleSmile = Smile, OpenSmile,
    BigSmile = OpenSmile, SadCurved
}

public record MascotExpression(
    MascotMood Mood,
    EyeShape EyeShape,
    MouthShape MouthShape,
    string Description = "Ready",
    double HeadTiltDegrees = 0,
    double EyeOffsetY = 0,
    double AntennaPulse = 0,
    double BreathingOffset = 0,
    bool IsAntennaGlowing = false,
    double EyeOffsetX = 0)
{
    public EyeShape Eye => EyeShape;
    public MouthShape Mouth => MouthShape;
    public int Priority => Mood switch
    {
        MascotMood.Alert => 98,
        MascotMood.Thinking => 78,
        MascotMood.Listening => 75,
        MascotMood.Focused => 74,
        MascotMood.Celebrating => 80,
        MascotMood.Surprised => 67,
        MascotMood.Grumpy => 66,
        MascotMood.Affection => 64,
        MascotMood.Concerned => 56,
        MascotMood.Music => 50,
        MascotMood.Excited => 46,
        MascotMood.Happy => 40,
        MascotMood.Curious => 35,
        MascotMood.Bored => 25,
        MascotMood.Sleepy => 20,
        _ => 10
    };

    // The Windows reference shows the welcoming online face: two soft happy
    // arcs and a tiny luminous smile. Other poses follow Character/Expression.swift.
    public static MascotExpression Idle(string description = "Ready to help") =>
        new(MascotMood.Idle, EyeShape.HappyArch, MouthShape.Smile, description, AntennaPulse: .25, IsAntennaGlowing: true);
    public static MascotExpression Focused(string description = "Focused") =>
        new(MascotMood.Focused, EyeShape.NarrowLine, MouthShape.Hidden, description, HeadTiltDegrees: 2, EyeOffsetY: -1, AntennaPulse: .5, IsAntennaGlowing: true);
    public static MascotExpression Happy(string description = "Happy") =>
        new(MascotMood.Happy, EyeShape.HappyArch, MouthShape.Smile, description, AntennaPulse: .5, IsAntennaGlowing: true);
    public static MascotExpression Thinking(string description = "Thinking") =>
        new(MascotMood.Thinking, EyeShape.NarrowLine, MouthShape.Hidden, description, HeadTiltDegrees: 7, EyeOffsetY: -2, AntennaPulse: .8, IsAntennaGlowing: true);
    public static MascotExpression Listening(string description = "Attentive") =>
        new(MascotMood.Listening, EyeShape.NormalDot, MouthShape.Hidden, description, HeadTiltDegrees: 2, AntennaPulse: .8, IsAntennaGlowing: true);
    public static MascotExpression Alert(string description = "Attention needed") =>
        new(MascotMood.Alert, EyeShape.WideCircle, MouthShape.Hidden, description, EyeOffsetY: -1, AntennaPulse: 1, IsAntennaGlowing: true);
    public static MascotExpression Create(MascotMood mood) => mood switch
    {
        MascotMood.Idle => Idle(),
        MascotMood.Focused => Focused(),
        MascotMood.Happy => Happy(),
        MascotMood.Thinking => Thinking(),
        MascotMood.Listening => Listening(),
        MascotMood.Alert => Alert(),
        MascotMood.Curious => new(mood, EyeShape.NormalDot, MouthShape.Hidden, "Curious", HeadTiltDegrees: 8, EyeOffsetY: -2, EyeOffsetX: 2, AntennaPulse: .5),
        MascotMood.Affection => new(mood, EyeShape.Heart, MouthShape.Smile, "Feeling affectionate", HeadTiltDegrees: 3, AntennaPulse: 1, IsAntennaGlowing: true),
        MascotMood.Grumpy => new(mood, EyeShape.SlantedGrumpy, MouthShape.NeutralSmall, "Playfully grumpy", HeadTiltDegrees: -6, AntennaPulse: .25),
        MascotMood.Surprised => new(mood, EyeShape.WideCircle, MouthShape.OpenSmile, "Surprised", AntennaPulse: .8),
        MascotMood.Celebrating => new(mood, EyeShape.HappyArch, MouthShape.Smile, "Celebrating", AntennaPulse: 1, IsAntennaGlowing: true),
        MascotMood.Excited => new(mood, EyeShape.HappyArch, MouthShape.Smile, "Excited", HeadTiltDegrees: 2, AntennaPulse: 1, IsAntennaGlowing: true),
        MascotMood.Music => new(mood, EyeShape.HappyArch, MouthShape.Smile, "Enjoying music", HeadTiltDegrees: -2, AntennaPulse: .5, IsAntennaGlowing: true),
        MascotMood.Bored => new(mood, EyeShape.HalfClosed, MouthShape.NeutralSmall, "Quietly waiting", HeadTiltDegrees: -3, AntennaPulse: .15),
        MascotMood.Sleepy => new(mood, EyeShape.BlinkClosed, MouthShape.Hidden, "Sleepy", HeadTiltDegrees: -6, AntennaPulse: .05),
        MascotMood.Concerned => new(mood, EyeShape.SadArc, MouthShape.Hidden, "Concerned", HeadTiltDegrees: -4, AntennaPulse: .3),
        _ => new(MascotMood.Neutral, EyeShape.NormalDot, MouthShape.Hidden, "Resting")
    };
}
