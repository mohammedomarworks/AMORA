using System.ComponentModel;
using AMORA.Orbit.Models;
using AMORA.Orbit.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using ShapePath = Microsoft.UI.Xaml.Shapes.Path;

namespace AMORA.Orbit.Views;

public sealed partial class RobotMascotView : UserControl
{
    private RobotMascotViewModel? _model;
    private Storyboard? _reactionMotion;
    private double _pointerX, _pointerY;
    private MascotMood? _lastMood;

    public RobotMascotView()
    {
        try
        {
            InitializeComponent();
            DataContextChanged += (_, args) => Bind(args.NewValue as RobotMascotViewModel);
            Loaded += (_, _) => Bind(DataContext as RobotMascotViewModel);
            Unloaded += (_, _) => { _reactionMotion?.Stop(); Bind(null); };
            Render(MascotExpression.Idle());
        }
        catch (Exception ex)
        {
            AMORA.Orbit.Services.Implementations.CrashLogger.LogException(ex, startupStage: "mascot-construction");
            throw;
        }
    }

    private void Bind(RobotMascotViewModel? model)
    {
        if (_model != null) _model.PropertyChanged -= OnExpressionChanged;
        _model = model;
        if (_model != null) { _model.PropertyChanged += OnExpressionChanged; Render(_model.Expression); }
    }

    private void OnExpressionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_model != null && e.PropertyName is nameof(RobotMascotViewModel.Expression)
            or nameof(RobotMascotViewModel.AnimationIntensity) or nameof(RobotMascotViewModel.IsAntennaGlowActive))
            Render(_model.Expression);
    }

    private double MotionScale
    {
        get
        {
            try { return new Windows.UI.ViewManagement.UISettings().AnimationsEnabled ? _model?.AnimationIntensity ?? 1 : 0; }
            catch { return 0; }
        }
    }

    // Only fixed application-owned vectors enter XAML. Detaching from the parser
    // host is required: each WinUI Geometry can have only one visual owner.
    private static Geometry Geometry(string data)
    {
        var path = (ShapePath)XamlReader.Load($"<Path xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Data='{data}'/>");
        var geometry = path.Data;
        path.Data = null;
        return geometry;
    }

    private static void ApplyEye(ShapePath eye, ShapePath glow, ShapePath bloom, string data, bool filled, Windows.UI.Color core)
    {
        eye.Data = Geometry(data);
        glow.Data = Geometry(data);
        bloom.Data = Geometry(data);
        eye.Stroke = new SolidColorBrush(core);
        eye.Fill = filled ? new SolidColorBrush(core) : null;
    }

    private void Render(MascotExpression expression)
    {
        string left = expression.EyeShape switch
        {
            EyeShape.HappyArch => "M 32,61 C 36,51 41,51 45,60",
            EyeShape.NarrowLine => "M 32,57 Q 38,55.5 45,57",
            EyeShape.BlinkClosed => "M 32,61 Q 38.5,64 45,61",
            EyeShape.HalfClosed => "M 33,58 L 44,58 L 44,61 L 33,61 Z",
            EyeShape.Heart => "M 38.5,65 C 23,56 31,47 38.5,54 C 46,47 54,56 38.5,65 Z",
            EyeShape.SlantedGrumpy => "M 32,54 L 45,59",
            EyeShape.SadArc => "M 32,55 Q 38.5,64 45,55",
            EyeShape.WideCircle => "M 34,51 Q 38.5,47 43,51 L 43,63 Q 38.5,67 34,63 Z",
            _ => "M 35,53 Q 38.5,50 42,53 L 42,62 Q 38.5,65 35,62 Z"
        };
        string right = expression.EyeShape switch
        {
            EyeShape.HappyArch => "M 61,60 C 65,51 70,51 74,61",
            EyeShape.NarrowLine => "M 61,57 Q 67,55.5 74,57",
            EyeShape.BlinkClosed => "M 61,61 Q 67.5,64 74,61",
            EyeShape.HalfClosed => "M 62,58 L 73,58 L 73,61 L 62,61 Z",
            EyeShape.Heart => "M 67.5,65 C 52,56 60,47 67.5,54 C 75,47 83,56 67.5,65 Z",
            EyeShape.SlantedGrumpy => "M 61,59 L 74,54",
            EyeShape.SadArc => "M 61,55 Q 67.5,64 74,55",
            EyeShape.WideCircle => "M 63,51 Q 67.5,47 72,51 L 72,63 Q 67.5,67 63,63 Z",
            _ => "M 64,53 Q 67.5,50 71,53 L 71,62 Q 67.5,65 64,62 Z"
        };
        var core = expression.Mood == MascotMood.Affection
            ? Windows.UI.Color.FromArgb(255, 255, 169, 205) : Windows.UI.Color.FromArgb(255, 237, 252, 255);
        bool filled = expression.EyeShape is EyeShape.NormalDot or EyeShape.WideCircle or EyeShape.HalfClosed or EyeShape.Heart;
        ApplyEye(LeftEye, LeftEyeGlow, LeftEyeBloom, left, filled, core);
        ApplyEye(RightEye, RightEyeGlow, RightEyeBloom, right, filled, core);
        var mouth = expression.MouthShape switch
        {
            MouthShape.SadCurved => "M 47,68 Q 52.5,62 58,68",
            MouthShape.NeutralSmall => "M 48,66 L 57,66",
            MouthShape.OpenSmile => "M 49,65 Q 52.5,62 56,65 L 56,68 Q 52.5,71 49,68 Z",
            _ => "M 46,61.5 Q 52,67 58,61.5"
        };
        Mouth.Data = Geometry(mouth);
        MouthBloom.Data = Geometry(mouth);
        Mouth.Visibility = MouthBloom.Visibility = expression.MouthShape == MouthShape.Hidden ? Visibility.Collapsed : Visibility.Visible;
        var motion = MotionScale;
        HeadTransform.Rotation = expression.HeadTiltDegrees * motion;
        GazeTransform.X = expression.EyeOffsetX + _pointerX * motion;
        GazeTransform.Y = expression.EyeOffsetY + _pointerY * motion;
        var sleepy = expression.Mood == MascotMood.Sleepy;
        LeftEye.Opacity = RightEye.Opacity = sleepy ? .6 : 1;
        LeftEyeGlow.Opacity = RightEyeGlow.Opacity = sleepy ? .08 : .24;
        Antenna.Opacity = sleepy ? .3 : 1;
        AntennaBloom.Opacity = _model?.IsAntennaGlowActive == false ? 0 : sleepy ? .025 : .1 + expression.AntennaPulse * .06;
        AntennaReaction.Visibility = expression.Mood is MascotMood.Affection or MascotMood.Grumpy or MascotMood.Alert ? Visibility.Visible : Visibility.Collapsed;
        AntennaReaction.Fill = new SolidColorBrush(expression.Mood == MascotMood.Affection
            ? Windows.UI.Color.FromArgb(255, 255, 140, 192) : Windows.UI.Color.FromArgb(255, 255, 167, 76));
        AutomationProperties.SetName(MascotButton, $"AMORA, {expression.Description}");
        if (_lastMood != expression.Mood)
        {
            _reactionMotion?.Stop();
            HeadTransform.TranslateY = 0;
            if (motion > 0 && expression.Mood is MascotMood.Affection or MascotMood.Excited or MascotMood.Celebrating or MascotMood.Happy)
                PlayBounce(motion, expression.Mood == MascotMood.Celebrating ? 4 : 2.5);
            _lastMood = expression.Mood;
        }
        if (motion == 0) { _reactionMotion?.Stop(); HeadTransform.TranslateY = 0; }
    }

    private void PlayBounce(double motion, double height)
    {
        var bounce = new DoubleAnimationUsingKeyFrames { EnableDependentAnimation = true };
        bounce.KeyFrames.Add(new EasingDoubleKeyFrame { KeyTime = TimeSpan.Zero, Value = 0 });
        bounce.KeyFrames.Add(new EasingDoubleKeyFrame { KeyTime = TimeSpan.FromMilliseconds(140), Value = -height * motion,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } });
        bounce.KeyFrames.Add(new EasingDoubleKeyFrame { KeyTime = TimeSpan.FromMilliseconds(340), Value = 0,
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut } });
        Storyboard.SetTarget(bounce, HeadTransform);
        Storyboard.SetTargetProperty(bounce, "TranslateY");
        _reactionMotion = new Storyboard();
        _reactionMotion.Children.Add(bounce);
        _reactionMotion.Begin();
    }

    private async void OnMascotClicked(object sender, RoutedEventArgs e)
    { if (_model != null) await _model.TriggerClickReactionAsync(); }
    private void OnMascotPointerEntered(object sender, PointerRoutedEventArgs e) => _model?.NoteInteraction();
    private void OnMascotPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        _model?.NoteInteraction();
        var point = e.GetCurrentPoint(MascotButton).Position;
        _pointerX = Math.Clamp((point.X / Math.Max(1, MascotButton.ActualWidth) - .5) * 4, -2, 2);
        _pointerY = Math.Clamp((point.Y / Math.Max(1, MascotButton.ActualHeight) - .5) * 3, -1.5, 1.5);
        if (_model != null)
        {
            GazeTransform.X = _model.Expression.EyeOffsetX + _pointerX * MotionScale;
            GazeTransform.Y = _model.Expression.EyeOffsetY + _pointerY * MotionScale;
        }
    }
    private void OnMascotPointerExited(object sender, PointerRoutedEventArgs e)
    { _pointerX = _pointerY = 0; if (_model != null) Render(_model.Expression); }
}
