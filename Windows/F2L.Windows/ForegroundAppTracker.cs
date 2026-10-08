using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace F2L.Windows;

internal sealed record ForegroundApp(IntPtr Window, uint Process);

/// <summary>Remembers window identity only. No screenshots or window contents are read here.</summary>
internal sealed class ForegroundAppTracker : IDisposable
{
    private readonly Func<IntPtr> _foreground;
    private readonly Func<IntPtr, ForegroundApp?> _candidate;
    private readonly Func<ForegroundApp, bool> _valid;
    private readonly WinEventCallback _callback;
    private readonly DispatcherTimer _fallback = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private ForegroundApp? _lastApp;
    private IntPtr _hook;
    private GCHandle _callbackRoot;
    private bool _disposed;

    internal ForegroundAppTracker(Func<IntPtr>? foreground = null, Func<IntPtr, ForegroundApp?>? candidate = null,
        Func<ForegroundApp, bool>? valid = null)
    {
        _foreground = foreground ?? NativeDesktop.GetForegroundWindow;
        _candidate = candidate ?? NativeDesktop.CaptureCandidate;
        _valid = valid ?? NativeDesktop.IsCaptureTargetValid;
        _callback = (_, _, window, _, _, _, _) => Observe(window);
        _fallback.Tick += (_, _) => RememberForeground();
    }

    internal void Start()
    {
        if (_disposed || _hook != IntPtr.Zero || _fallback.IsEnabled) return;
        RememberForeground();
        _callbackRoot = GCHandle.Alloc(_callback);
        // EVENT_SYSTEM_FOREGROUND; out of context, skipping our own process.
        // The registering WPF thread owns the callback and its message loop.
        _hook = SetWinEventHook(3, 3, IntPtr.Zero, _callback, 0, 0, 2);
        _fallback.Start();
    }

    internal void RememberForeground() => Observe(_foreground());

    internal void Observe(IntPtr window)
    {
        if (_disposed) return;
        var target = _candidate(window);
        if (target is not null) _lastApp = target;
    }

    internal ForegroundApp? GetTarget()
    {
        if (_disposed) return null;
        RememberForeground();
        if (_lastApp is not null && !_valid(_lastApp)) _lastApp = null;
        return _lastApp;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _fallback.Stop();
        if (_hook != IntPtr.Zero) { UnhookWinEvent(_hook); _hook = IntPtr.Zero; }
        if (_callbackRoot.IsAllocated) _callbackRoot.Free();
        _lastApp = null;
    }

    private delegate void WinEventCallback(IntPtr hook, uint eventType, IntPtr window, int objectId, int childId, uint thread, uint time);
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint first, uint last, IntPtr module,
        WinEventCallback callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);
}
