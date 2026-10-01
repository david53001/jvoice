using System.Windows;
using System.Windows.Threading;
using JVoice.Core.Tours;

namespace JVoice.App.Tours;

/// <summary>
/// The one-way line from the app's surfaces to the tour system (Mac <c>TourEvents</c>). Surfaces call these at the
/// moments tours care about; <see cref="Coordinator"/> is set by the app at startup. With none set (previews, renders,
/// probes) every call is a no-op, so posting is always safe.
/// </summary>
public static class TourEvents
{
    public static TourCoordinator? Coordinator { get; set; }

    public static void Post(TourEvent e) => Coordinator?.Post(e);

    public static void PostAction(string name) => Post(TourEvent.Action(name));

    /// <summary>Call right after a surface's window is on screen (laid out).</summary>
    public static void SurfaceShown(TourSurface surface, Window window) =>
        Coordinator?.SurfaceShown(surface, WindowTourHost.For(window));

    /// <summary>The ⓘ's Replay Tour (with its window) or Help &amp; Tours (null: now if on screen, else when it next shows).</summary>
    public static void Replay(TourId tour, Window? window) =>
        Coordinator?.Replay(tour, window is null ? null : WindowTourHost.For(window));

    /// <summary>The ⓘ's Show Me ▸ list: explain just step <paramref name="step"/> of <paramref name="tour"/>.</summary>
    public static void ReplayPart(TourId tour, int step, Window? window) =>
        Coordinator?.ReplayPart(tour, step, window is null ? null : WindowTourHost.For(window));

    /// <summary>Help &amp; Tours / Settings → Tours &amp; Tips → Reset All Tours (clears seen + paused, confirms in the HUD).</summary>
    public static void ResetAll() => Coordinator?.ResetAllToursAndConfirm();

    internal static void HostClosed(ITourHost host) => Coordinator?.HostClosed(host);
}

/// <summary>The coordinator's timers on the UI dispatcher.</summary>
public sealed class DispatcherTourClock : ITourClock
{
    private readonly Dispatcher _dispatcher;

    public DispatcherTourClock(Dispatcher dispatcher) => _dispatcher = dispatcher;

    public void After(TimeSpan delay, Action action)
    {
        var t = new DispatcherTimer(DispatcherPriority.Normal, _dispatcher) { Interval = delay };
        t.Tick += (_, _) => { t.Stop(); action(); };
        t.Start();
    }

    public IDisposable Every(TimeSpan interval, Action action)
    {
        var t = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = interval };
        t.Tick += (_, _) => action();
        t.Start();
        return new Stopper(t);
    }

    public void Post(Action action) => _dispatcher.BeginInvoke(DispatcherPriority.Background, action);

    private sealed class Stopper(DispatcherTimer timer) : IDisposable
    {
        public void Dispose() => timer.Stop();
    }
}
