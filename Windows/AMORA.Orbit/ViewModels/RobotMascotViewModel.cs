using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.ViewModels;

public class RobotMascotViewModel : INotifyPropertyChanged
{
    private MascotExpression _expression = MascotExpression.Idle();
    private bool _isAntennaGlowActive = true;
    private string _statusSubtext = "Ready to help";

    public MascotExpression Expression
    {
        get => _expression;
        set
        {
            if (_expression != value)
            {
                _expression = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(Mood));
                OnPropertyChanged(nameof(StatusDescription));
            }
        }
    }

    public MascotMood Mood => _expression.Mood;
    public string StatusDescription => _expression.Description;

    public bool IsAntennaGlowActive
    {
        get => _isAntennaGlowActive;
        set
        {
            if (_isAntennaGlowActive != value)
            {
                _isAntennaGlowActive = value;
                OnPropertyChanged();
            }
        }
    }

    public string StatusSubtext
    {
        get => _statusSubtext;
        set
        {
            if (_statusSubtext != value)
            {
                _statusSubtext = value;
                OnPropertyChanged();
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void SetMood(MascotMood mood, string? customDescription = null)
    {
        Expression = mood switch
        {
            MascotMood.Focused => MascotExpression.Focused(customDescription ?? "Deep Focus"),
            MascotMood.Happy => MascotExpression.Happy(customDescription ?? "Delighted"),
            MascotMood.Listening => MascotExpression.Listening(customDescription ?? "Listening..."),
            MascotMood.Thinking => MascotExpression.Thinking(customDescription ?? "Thinking..."),
            MascotMood.Alert => MascotExpression.Alert(customDescription ?? "Attention Needed"),
            _ => MascotExpression.Idle(customDescription ?? "Ready")
        };
    }

    public async Task TriggerClickReactionAsync()
    {
        var previous = _expression;
        Expression = MascotExpression.Happy("Nice to see you!");
        await Task.Delay(1400);
        Expression = previous;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
