using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Pip conducts a bouncing wordmark, then walks home. Mirrors Sources/F2L/Intro.swift.</summary>
internal sealed class IntroWindow : Window
{
    internal const string TitleText = "F2L AI";
    internal const string Subtitle = "A teaching companion";
    private const double WalkStart = 3.7, WalkDuration = 2.35;
    private sealed class Artwork : FrameworkElement
    {
        internal Action<DrawingContext>? Paint;
        protected override void OnRender(DrawingContext dc) => Paint?.Invoke(dc);
    }

    private readonly Canvas _stage = new() { Background = Brushes.Transparent };
    private readonly Artwork _artwork = new();
    private readonly PipView _pip = new();
    private readonly Button _skip;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly Stopwatch _clock = new();
    private readonly Rect _home;
    private readonly bool _reducedMotion;
    private readonly Typeface _regular, _semibold;
    private Action? _completion;
    private bool _finished;
    private double _seconds;

    internal IntroWindow(Rect home, bool reducedMotion)
    {
        _home = home; _reducedMotion = reducedMotion;
        var font = Application.Current.TryFindResource("UiFont") as FontFamily ?? new FontFamily("Segoe UI");
        _regular = new Typeface(font, FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);
        _semibold = new Typeface(font, FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
        Title = TitleText;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = 0; Top = 0; Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight;
        _artwork.Width = Width; _artwork.Height = Height;
        _artwork.Paint = Paint;
        _stage.Children.Add(_artwork); _stage.Children.Add(_pip); Content = _stage;
        AutomationProperties.SetName(_stage, $"{TitleText}. {Subtitle}. Click to skip.");
        // An accessible skip button also provides an explicit UI Automation invoke target.
        _skip = new Button { Content = "Skip intro", Opacity = 0.65, Background = Brushes.Transparent, Foreground = Brushes.White,
            BorderThickness = new Thickness(0), FontSize = 12, Padding = new Thickness(12, 8), Cursor = System.Windows.Input.Cursors.Hand };
        Canvas.SetLeft(_skip, Width - 100); Canvas.SetTop(_skip, 24);
        _skip.Click += (_, _) => Finish(); _stage.Children.Add(_skip);
        _pip.SetReducedMotion(reducedMotion);
        MouseLeftButtonDown += (_, _) => Finish();
        _timer.Tick += (_, _) => Tick();
        Closed += (_, _) => _timer.Stop();
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            SetWindowLongPtr(handle, -20, new IntPtr(GetWindowLongPtr(handle, -20).ToInt64() | 0x08000000L));
        };
    }

    internal void Play(Action completion)
    {
        _completion = completion;
        Tick(0); Show(); _clock.Restart(); _timer.Start();
    }

    private static double Ease(double x) { x = Math.Clamp(x, 0, 1); return x * x * (3 - 2 * x); }
    private static double Spring(double x) { x = Math.Clamp(x, 0, 1); return x == 1 ? 1 : 1 - Math.Exp(-6 * x) * Math.Cos(10 * x); }
    private double WalkProgress => _reducedMotion ? 0 : Ease((_seconds - WalkStart) / WalkDuration);
    private double BackdropAlpha => _reducedMotion ? Math.Min(Ease(_seconds / 0.2), 1 - Ease((_seconds - 1.55) / 0.25))
        : Ease(_seconds / 0.3) * (1 - Ease((_seconds - WalkStart) / 0.85));
    private (double Unit, Point Origin, Rect Pip) Layout()
    {
        var unit = Math.Min(1, Math.Min(Width / 850, Height / 560));
        var origin = new Point((Width - 610 * unit) / 2, Height * 0.44 - 76 * unit);
        return (unit, origin, new Rect(origin.X + 396 * unit, origin.Y - 32 * unit, 202 * unit, 215 * unit));
    }

    private Rect PipRect(double p)
    {
        var (unit, _, start) = Layout();
        var end = new Rect(_home.X - Left, _home.Y - Top, _home.Width, _home.Height);
        var arc = Math.Sin(p * Math.PI) * 48 * unit;
        var stride = Math.Sin(p * Math.PI * 14) * 4 * Math.Sin(p * Math.PI);
        return new Rect(start.X + (end.X - start.X) * p, start.Y + (end.Y - start.Y) * p - arc + stride,
            start.Width + (end.Width - start.Width) * p, start.Height + (end.Height - start.Height) * p);
    }

    internal void Tick(double? at = null)
    {
        _seconds = Math.Max(0, at ?? _clock.Elapsed.TotalSeconds);
        if (at is null && _seconds >= (_reducedMotion ? 1.8 : WalkStart + WalkDuration)) { Finish(); return; }
        var (_, _, start) = Layout();
        Rect rect;
        if (_seconds < WalkStart || _reducedMotion)
        {
            var pop = _reducedMotion ? 1 : Spring((_seconds - 0.08) / 0.7);
            var scale = 0.55 + 0.45 * pop;
            var conducting = _reducedMotion ? 0 : Math.Sin(Math.Max(0, _seconds - 0.3) * 11) * 5 * Ease((_seconds - 0.3) / 0.2) * (1 - Ease((_seconds - 2.1) / 0.4));
            rect = new Rect(start.X + start.Width / 2 - start.Width * scale / 2, start.Bottom - start.Height * scale + conducting,
                start.Width * scale, start.Height * scale);
            _pip.Opacity = _reducedMotion ? BackdropAlpha : Ease((_seconds - 0.08) / 0.2);
            _pip.SetTravelling(PointingDirection.None); _pip.SetWaving(true);
        }
        else
        {
            _pip.SetWaving(false);
            var dx = _home.X + _home.Width / 2 - Left - start.X - start.Width / 2;
            _pip.SetTravelling(WalkProgress < 0.99 ? (Math.Abs(dx) > 80 ? (dx < 0 ? PointingDirection.Left : PointingDirection.Right) : PointingDirection.Down) : PointingDirection.None);
            rect = PipRect(WalkProgress); _pip.Opacity = 1;
        }
        _pip.Width = rect.Width; _pip.Height = rect.Height;
        Canvas.SetLeft(_pip, rect.X); Canvas.SetTop(_pip, rect.Y);
        _skip.Opacity = 0.65 * BackdropAlpha;
        _artwork.InvalidateVisual();
    }

    private static SolidColorBrush Ink(uint hex, double alpha = 1) => new(Color.FromArgb((byte)(255 * Math.Clamp(alpha, 0, 1)), (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex));
    private FormattedText Text(string value, double size, Brush ink, bool bold = false) => new(value, CultureInfo.CurrentUICulture,
        FlowDirection.LeftToRight, bold ? _semibold : _regular, size, ink, VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private void Paint(DrawingContext dc)
    {
        var (unit, origin, start) = Layout();
        var alpha = BackdropAlpha;
        dc.DrawRectangle(Ink(0x191923, 0.94 * alpha), null, new Rect(0, 0, Width, Height));
        if (alpha > 0)
        {
            var glow = new RadialGradientBrush(Ink(0x827088, 0.27 * alpha).Color, Colors.Transparent);
            dc.DrawEllipse(glow, null, new Point(origin.X + 300 * unit, origin.Y + 80 * unit), 440 * unit, 300 * unit);
        }
        var exit = _reducedMotion ? 0 : Ease((_seconds - 3.08) / 0.5);
        var letters = new[] { "F", "2", "L", "A", "I" };
        var x = origin.X;
        for (var i = 0; i < letters.Length; i++)
        {
            if (i == 3) x += 23 * unit;
            var width = Text(letters[i], 88 * unit, Brushes.White, true).Width;
            var appear = _reducedMotion ? 1 : Spring((_seconds - 0.32 - i * 0.15) / 0.65);
            var opacity = _reducedMotion ? alpha : Ease((_seconds - 0.32 - i * 0.15) / 0.18) * (1 - Ease((_seconds - 3.05 - i * 0.065) / 0.4));
            var lift = _reducedMotion ? 0 : 58 * (1 - appear) - 24 * Ease((_seconds - 3.05 - i * 0.065) / 0.4);
            DrawText(dc, letters[i], new Point(x + width / 2, origin.Y + 54 * unit + lift * unit), 88 * unit,
                Ink(i < 3 ? 0xFFFAF3u : 0xEDC98Fu, opacity), _reducedMotion ? 1 : 0.72 + 0.28 * appear,
                _reducedMotion ? 0 : (i % 2 == 0 ? -0.12 : 0.1) * (1 - appear), true);
            var burst = (_seconds - 0.66 - i * 0.15) / 0.45;
            if (!_reducedMotion && burst > 0 && burst < 1)
                Spark(dc, new Point(x + width * 0.7, origin.Y - 8 * unit - 15 * burst * unit), (3 + 5 * burst) * unit, Math.Sin(burst * Math.PI) * 0.7);
            x += width + 3 * unit;
        }
        var wordX = origin.X + 3 * unit;
        var words = Subtitle.Split(' ');
        for (var i = 0; i < words.Length; i++)
        {
            var width = Text(words[i], 23 * unit, Brushes.White).Width;
            var p = _reducedMotion ? 1 : Spring((_seconds - 1.3 - i * 0.16) / 0.55);
            var opacity = _reducedMotion ? alpha : Ease((_seconds - 1.3 - i * 0.16) / 0.18) * (1 - exit);
            DrawText(dc, words[i], new Point(wordX + width / 2, origin.Y + 129 * unit + (_reducedMotion ? 0 : 24 * (1 - p) * unit)),
                23 * unit, Ink(0xDED7E8, opacity));
            wordX += width + 7 * unit;
        }
        var stroke = _reducedMotion ? 1 : Ease((_seconds - 1.7) / 0.65);
        if (stroke > 0)
        {
            var path = new StreamGeometry();
            using (var context = path.Open())
            {
                context.BeginFigure(new Point(origin.X + 4 * unit, origin.Y + 163 * unit), false, false);
                context.BezierTo(new Point(origin.X + 80 * stroke * unit, origin.Y + 169 * unit),
                    new Point(origin.X + 210 * stroke * unit, origin.Y + 153 * unit),
                    new Point(origin.X + (4 + 300 * stroke) * unit, origin.Y + 161 * unit), true, false);
            }
            dc.DrawGeometry(null, new Pen(Ink(0xEDC98F, 0.7 * (_reducedMotion ? alpha : 1 - exit)), 2.5 * unit) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, path);
            Spark(dc, new Point(origin.X + 324 * unit, origin.Y + 160 * unit), 6 * unit, stroke * (_reducedMotion ? alpha : 1 - exit));
        }
        if (!_reducedMotion)
        {
            for (var i = 0; i < 5; i++)
            {
                var phase = _seconds * 1.3 + i * 1.8;
                Spark(dc, new Point(start.X + start.Width / 2 + Math.Cos(i * 2.1) * 135 * unit,
                    start.Y + start.Height / 2 + Math.Sin(i * 2.1) * 110 * unit + Math.Sin(phase) * 8 * unit),
                    (i % 2 == 0 ? 5 : 3) * unit, Ease((_seconds - 0.6) / 0.5) * alpha * (0.35 + 0.2 * Math.Sin(phase)));
            }
            for (var i = 0; i < 12; i++)
            {
                var born = WalkStart + i * 0.17;
                var age = _seconds - born;
                if (age < 0 || age >= 0.6) continue;
                var rect = PipRect(Ease((born - WalkStart) / WalkDuration));
                Spark(dc, new Point(rect.X + rect.Width / 2, rect.Bottom - 9), 4 * (1 - age / 0.6), (1 - age / 0.6) * 0.65);
            }
        }
        DrawText(dc, "Click anywhere to skip", new Point(Width / 2, Height - 42), 12, Ink(0xDBD5E3, alpha * 0.6));
    }

    private void DrawText(DrawingContext dc, string value, Point center, double size, Brush ink, double scale = 1, double angle = 0, bool bold = false)
    {
        var text = Text(value, size, ink, bold);
        dc.PushTransform(new TranslateTransform(center.X, center.Y));
        dc.PushTransform(new RotateTransform(angle * 180 / Math.PI));
        dc.PushTransform(new ScaleTransform(scale, scale));
        dc.DrawText(text, new Point(-text.Width / 2, -text.Height / 2));
        dc.Pop(); dc.Pop(); dc.Pop();
    }

    private static void Spark(DrawingContext dc, Point center, double radius, double opacity)
    {
        var path = new StreamGeometry();
        using (var context = path.Open())
        {
            for (var i = 0; i < 8; i++)
            {
                var angle = i * Math.PI / 4;
                var r = i % 2 == 0 ? radius : radius * 0.24;
                var point = new Point(center.X + Math.Cos(angle) * r, center.Y + Math.Sin(angle) * r);
                if (i == 0) context.BeginFigure(point, true, true); else context.LineTo(point, true, false);
            }
        }
        dc.DrawGeometry(Ink(0xF4D79D, opacity), null, path);
    }

    internal void Finish()
    {
        if (_finished) return;
        _finished = true; _timer.Stop();
        var completion = _completion; _completion = null;
        Close(); completion?.Invoke();
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
}
