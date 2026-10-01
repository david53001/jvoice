using System.Diagnostics;
using System.Windows.Threading;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// The Settings tour's Opacity step (parity §10.8; Mac <c>OpacityTourDemo.swift</c>, David 2026-09-30: "show the bar
/// slowly going down… how the opacity decreased and increased"): the REAL Opacity value glides along the pure
/// <see cref="OpacityDemoTimeline"/> — user's value → Transparent → Opaque → back, looping — so the slider moves and
/// every window follows live, while the tag reads it out ("Watch: 37 % ↓").
///
/// Never saves: the coordinator holds the stored value while it plays, and <see cref="Stop"/> puts the user's value
/// back. Moving the slider (or pressing Default) during the demo hands it back to the user — their value is kept and
/// saved. Runs a 60 fps timer only while the step is on screen.
/// </summary>
public sealed class OpacityTourDemo : ITourStepDemo
{
    private readonly VoiceCoordinator _coordinator;
    private DispatcherTimer? _timer;
    private readonly Stopwatch _clock = new();
    private double _original;
    private double? _lastSet;
    private Action<string>? _readout;
    private string _lastReadout = "";

    public OpacityTourDemo(VoiceCoordinator coordinator) => _coordinator = coordinator;

    public void Start(Action<string> readout)
    {
        Stop();
        _readout = readout;
        _original = _coordinator.UiOpacity;
        _coordinator.BeginOpacityHold();
        _clock.Restart();
        _lastReadout = "";
        Tick();
        _timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(1000.0 / 60) };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    public void Stop()
    {
        if (_timer is null) return;
        _timer.Stop();
        _timer = null;
        _readout = null;
        // Only undo the demo's own change; a value the user set meanwhile stays.
        if (_lastSet is { } last && Math.Abs(_coordinator.UiOpacity - last) < 1e-9) _coordinator.UiOpacity = _original;
        _lastSet = null;
        _coordinator.EndOpacityHold();
    }

    private void Tick()
    {
        if (_lastSet is { } last && Math.Abs(_coordinator.UiOpacity - last) > 1e-9)
        {
            // The user moved the slider or pressed Default: their value wins and is saved.
            _timer?.Stop();
            _timer = null;
            _readout = null;
            _lastSet = null;
            _coordinator.EndOpacityHold();
            return;
        }
        var frame = OpacityDemoTimeline.FrameAt(_clock.Elapsed.TotalSeconds, _original);
        _lastSet = JVoice.Core.UiOpacity.Clamp(frame.Value);
        _coordinator.UiOpacity = frame.Value;
        if (frame.Readout != _lastReadout)
        {
            _lastReadout = frame.Readout;
            _readout?.Invoke(frame.Readout);
        }
    }
}
