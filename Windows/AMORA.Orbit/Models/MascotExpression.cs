namespace AMORA.Orbit.Models;

/// <summary>
/// Expressive mood states for AMORA's vector robot mascot.
/// </summary>
public enum MascotMood
{
    Neutral,
    Idle,
    Focused,
    Happy,
    Thinking,
    Curious,
    Affection,
    Grumpy,
    Surprised,
    Listening,
    Alert,
    Celebrating
}

public enum EyeShape
{
    NormalDot,
    Circle = NormalDot,
    HappyArch,
    HappyArcs = HappyArch,
    NarrowLine,
    Narrowed = NarrowLine,
    Heart,
    WideCircle,
    Wide = WideCircle,
    SlantedGrumpy,
    BlinkClosed
}

public enum MouthShape
{
    Hidden,
    NeutralSmall,
    Smile,
    GentleSmile = Smile,
    OpenSmile,
    BigSmile = OpenSmile,
    SadCurved
}

/// <summary>
/// Complete physical expression model of the robot's eyes, mouth, antenna, and head physics.
/// </summary>
public record MascotExpression(
    MascotMood Mood,
    EyeShape EyeShape,
    MouthShape MouthShape,
    string Description = "Ready",
    double HeadTiltDegrees = 0.0,
    double EyeOffsetY = 0.0,
    double AntennaPulse = 0.0,
    double BreathingOffset = 0.0,
    bool IsAntennaGlowing = false
)
{
    public EyeShape Eye => EyeShape;
    public MouthShape Mouth => MouthShape;

    public static MascotExpression Idle(string description = "Ready") =>
        new(MascotMood.Idle, EyeShape.Circle, MouthShape.GentleSmile, Description: description);

    public static MascotExpression Focused(string description = "Deep Focus") =>
        new(MascotMood.Focused, EyeShape.Narrowed, MouthShape.Hidden, Description: description, HeadTiltDegrees: 1.0, AntennaPulse: 0.5, IsAntennaGlowing: true);

    public static MascotExpression Happy(string description = "Delighted") =>
        new(MascotMood.Happy, EyeShape.HappyArcs, MouthShape.BigSmile, Description: description, HeadTiltDegrees: 2.0);

    public static MascotExpression Thinking(string description = "Thinking...") =>
        new(MascotMood.Thinking, EyeShape.Narrowed, MouthShape.NeutralSmall, Description: description, HeadTiltDegrees: 5.0, EyeOffsetY: -2.0, AntennaPulse: 0.8, IsAntennaGlowing: true);

    public static MascotExpression Listening(string description = "Listening...") =>
        new(MascotMood.Listening, EyeShape.NormalDot, MouthShape.NeutralSmall, Description: description, HeadTiltDegrees: 1.0, AntennaPulse: 0.9, IsAntennaGlowing: true);

    public static MascotExpression Alert(string description = "Attention Needed") =>
        new(MascotMood.Alert, EyeShape.Wide, MouthShape.OpenSmile, Description: description, EyeOffsetY: -1.0, AntennaPulse: 1.0, IsAntennaGlowing: true);

    public static MascotExpression Create(MascotMood mood) => mood switch
    {
        MascotMood.Idle => Idle(),
        MascotMood.Focused => Focused(),
        MascotMood.Happy => Happy(),
        MascotMood.Thinking => Thinking(),
        MascotMood.Curious => new(MascotMood.Curious, EyeShape.NormalDot, MouthShape.NeutralSmall, "Curious", HeadTiltDegrees: 8.0, EyeOffsetY: -3.0, AntennaPulse: 0.4),
        MascotMood.Affection => new(MascotMood.Affection, EyeShape.Heart, MouthShape.Smile, "Affectionate", HeadTiltDegrees: 3.0, AntennaPulse: 1.0, IsAntennaGlowing: true),
        MascotMood.Grumpy => new(MascotMood.Grumpy, EyeShape.SlantedGrumpy, MouthShape.SadCurved, "Grumpy", HeadTiltDegrees: -4.0),
        MascotMood.Surprised => new(MascotMood.Surprised, EyeShape.WideCircle, MouthShape.OpenSmile, "Surprised", EyeOffsetY: -1.0, AntennaPulse: 0.8),
        MascotMood.Listening => Listening(),
        MascotMood.Alert => Alert(),
        MascotMood.Celebrating => new(MascotMood.Celebrating, EyeShape.HappyArch, MouthShape.OpenSmile, "Celebrating", HeadTiltDegrees: 5.0, AntennaPulse: 1.0, IsAntennaGlowing: true),
        _ => new(MascotMood.Neutral, EyeShape.NormalDot, MouthShape.Hidden, "Neutral")
    };
}
