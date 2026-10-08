using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>A non-activating, click-through presentation of the same Pip while teaching.</summary>
internal sealed class TeachingCompanionWindow : Window
{
    internal PipView Pip { get; } = new();
    private readonly DispatcherTimer _motion = new() { Interval = TimeSpan.FromMilliseconds(80) };
    private readonly Stopwatch _clock = new();
    private Rect _from, _destination, _protected, _panel = Rect.Empty;
    private double _scale = 1;
    internal Action? Moved { get; set; }
    internal Rect ScreenBounds { get; private set; }
    internal bool ReducedMotion { get; set; }

    internal TeachingCompanionWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        IsHitTestVisible = false;
        Content = Pip;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = GetWindowLongPtr(handle, -20).ToInt64();
            SetWindowLongPtr(handle, -20, new IntPtr(style | 0x20L | 0x80L | 0x08000000L));
        };
        _motion.Tick += (_, _) => Tick();
        Closed += (_, _) => _motion.Stop();
    }

    internal void Follow(CompanionSpot spot, Rect target, double scale, Rect? origin = null, Rect? panel = null)
    {
        _scale = scale;
        _panel = panel ?? Rect.Empty;
        _protected = CompanionPlacement.ProtectedArea(target, scale);
        Pip.SetPointing(spot.Direction);
        Pip.SetReducedMotion(ReducedMotion);
        if (IsVisible && (_destination.TopLeft - spot.Bounds.TopLeft).Length < 2 && _destination.Size == spot.Bounds.Size) return;
        _from = IsVisible ? ScreenBounds : origin is { } start
            ? new Rect(start.Left, start.Top, spot.Bounds.Width, spot.Bounds.Height) : spot.Bounds;
        _destination = spot.Bounds;
        if (ReducedMotion) _from = _destination;
        MoveNative(_from);
        if (!IsVisible) Show();
        _clock.Restart();
        _motion.Interval = TimeSpan.FromMilliseconds(16);
        _motion.Start();
        Tick();
    }

    private void Tick()
    {
        var t = Math.Clamp(_clock.Elapsed.TotalMilliseconds / 300, 0, 1);
        var eased = 1 - Math.Pow(1 - t, 3);
        Pip.SetTravelling(t < 1 && !ReducedMotion ? TravelDirection() : PointingDirection.None);
        var x = _from.X + (_destination.X - _from.X) * eased;
        var y = _from.Y + (_destination.Y - _from.Y) * eased;
        var bounds = new Rect(x, y, _destination.Width, _destination.Height);
        if (ScreenBounds != bounds) MoveNative(bounds);
        // Pass clicks through, and disappear before the pointer or a text caret reaches the artwork.
        Opacity = CompanionPlacement.ShouldYield(ScreenBounds, _protected, NativeDesktop.CursorPosition,
            NativeDesktop.ActiveCaretBounds(), _scale) || (!_panel.IsEmpty && ScreenBounds.IntersectsWith(_panel)) ? 0 : 1;
        if (t >= 1) _motion.Interval = TimeSpan.FromMilliseconds(80);
    }

    private PointingDirection TravelDirection()
    {
        var dx = _destination.X - _from.X; var dy = _destination.Y - _from.Y;
        return Math.Abs(dx) > Math.Abs(dy) ? (dx < 0 ? PointingDirection.Left : PointingDirection.Right)
            : (dy < 0 ? PointingDirection.Up : PointingDirection.Down);
    }

    private void MoveNative(Rect pixels)
    {
        var handle = new WindowInteropHelper(this).EnsureHandle();
        NativeDesktop.SetWindowPos(handle, new IntPtr(-1), (int)Math.Round(pixels.X), (int)Math.Round(pixels.Y), 0, 0, 0x0011);
        var dpi = NativeDesktop.GetDpiForWindow(handle);
        var scale = (dpi == 0 ? 96 : dpi) / 96d;
        Width = pixels.Width / scale; Height = pixels.Height / scale;
        NativeDesktop.SetWindowPos(handle, new IntPtr(-1), (int)Math.Round(pixels.X), (int)Math.Round(pixels.Y),
            (int)Math.Round(pixels.Width), (int)Math.Round(pixels.Height), 0x0010);
        ScreenBounds = pixels;
        Moved?.Invoke();
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
}
