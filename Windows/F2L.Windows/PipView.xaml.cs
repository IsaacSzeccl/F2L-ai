using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

public partial class PipView : UserControl
{
    private readonly DispatcherTimer _animation = new() { Interval = TimeSpan.FromMilliseconds(80) };
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly int _personalitySeed = Random.Shared.Next(65_536);
    private QuestionIntent _intent;
    private PointingDirection _pointing, _travelling;
    private bool _speaking, _listening, _thinking, _waving, _reducedMotion;
    private string _lastFrame = "";
    internal string CurrentFrame => _lastFrame;

    public PipView()
    {
        InitializeComponent();
        _animation.Tick += (_, _) => DrawFrame();
        // Animate only while Pip is on screen; a hidden resting Pip should cost nothing.
        Loaded += (_, _) => { DrawFrame(); if (IsVisible) _animation.Start(); };
        Unloaded += (_, _) => _animation.Stop();
        IsVisibleChanged += (_, _) =>
        {
            if (IsVisible && IsLoaded) { DrawFrame(); _animation.Start(); }
            else _animation.Stop();
        };
        DrawFrame();
    }

    internal void SetExpression(QuestionIntent intent) { if (_intent == intent) return; _intent = intent; _clock.Restart(); DrawFrame(); }
    internal void SetSpeaking(bool speaking) { if (_speaking == speaking) return; _speaking = speaking; _clock.Restart(); DrawFrame(); }
    internal void SetListening(bool listening) { if (_listening == listening) return; _listening = listening; _clock.Restart(); DrawFrame(); }
    internal void SetThinking(bool thinking) { if (_thinking == thinking) return; _thinking = thinking; _clock.Restart(); DrawFrame(); }
    internal void SetWaving(bool waving) { if (_waving == waving) return; _waving = waving; _clock.Restart(); DrawFrame(); }
    internal void SetPointing(PointingDirection direction) { if (_pointing == direction) return; _pointing = direction; _clock.Restart(); DrawFrame(); }
    internal void SetTravelling(PointingDirection direction) { if (_travelling == direction) return; _travelling = direction; _clock.Restart(); DrawFrame(); }
    internal void SetReducedMotion(bool reduced) { if (_reducedMotion == reduced) return; _reducedMotion = reduced; _clock.Restart(); DrawFrame(); }

    private void DrawFrame()
    {
        var time = _reducedMotion ? 0 : (int)(_clock.ElapsedMilliseconds % 1000000);
        var directions = false;
        var playful = false;
        var mirror = false;
        int frame;
        if (_travelling != PointingDirection.None && !_reducedMotion)
        {
            directions = true;
            frame = _travelling is PointingDirection.Up or PointingDirection.Down ? 12 + time / 250 % 2 : 10 + time / 170 % 2;
            mirror = _travelling == PointingDirection.Left;
        }
        else if (_pointing != PointingDirection.None)
        {
            directions = true;
            frame = _pointing switch { PointingDirection.Left => 0, PointingDirection.Right => 2, PointingDirection.Up => 4, _ => 6 };
            // The alternate up frame lowers the arm, so hold the verified upward pose.
            if (_speaking && !_reducedMotion && _pointing != PointingDirection.Up) frame += time / 200 % 2;
        }
        else if (_waving) frame = _reducedMotion ? 14 : Sequence(time, [14, 15], [420, 420]);
        else if (_listening) frame = Sequence(time, [8, 9, 10, 11], [1100, 800, 120, 1400]);
        else if (_thinking) frame = Sequence(time, [4, 5, 6, 7], [1000, 800, 120, 800]);
        else if (_speaking && !_reducedMotion) frame = Sequence(time, [2, 3, 2, 0], [180, 140, 180, 140]);
        else if (!_reducedMotion && _intent == QuestionIntent.QuickFact && PlayfulFrame(_clock.ElapsedMilliseconds, _personalitySeed) is int idleFrame)
        {
            playful = true;
            frame = idleFrame;
        }
        else frame = _intent switch
        {
            QuestionIntent.MultiPart => Sequence(time, [4, 5, 6, 7], [1600, 1000, 120, 1000]),
            QuestionIntent.ClarificationNeeded => Sequence(time, [8, 9, 10, 11], [1800, 900, 120, 1200]),
            QuestionIntent.Procedural => Sequence(time, [12, 13], [3600, 650]),
            _ => Sequence(time, [0, 1], [3900, 130]),
        };
        var key = $"{(directions ? "direction" : playful ? "playful" : "expression")}:{frame}:{mirror}";
        if (_lastFrame == key) return;
        var sprite = (directions ? PipSprites.Directions : playful ? PipSprites.Playful : PipSprites.Expressions)[frame];
        Sprite.Source = sprite.Image;
        Sprite.Width = sprite.Width; Sprite.Height = sprite.Height;
        Canvas.SetLeft(Sprite, (320 - sprite.Width) / 2);
        Canvas.SetTop(Sprite, 325 - sprite.Height);
        Sprite.RenderTransformOrigin = new Point(0.5, 0.5);
        Sprite.RenderTransform = mirror ? new ScaleTransform(-1, 1) : Transform.Identity;
        _lastFrame = key;
    }

    // Mirrors CoachCore.PipPose.playfulFrame. Randomize once per view, never on an animation tick.
    internal static int? PlayfulFrame(long milliseconds, int seed)
    {
        var time = Math.Max(0, milliseconds);
        seed = Math.Max(0, seed) % 65_536;
        var cycle = time / 12_000;
        var delay = 6_000 + (seed * 73 + cycle % 3_000 * 997) % 3_000;
        var elapsed = time % 12_000 - delay;
        if (elapsed < 0 || elapsed >= 2_200) return null;
        var activity = (seed % 4 + cycle % 4 * (1 + seed / 4 % 2 * 2)) % 4;
        return (int)activity * 4 + Sequence((int)elapsed, [0, 1, 2, 3], [350, 650, 650, 550]);
    }

    private static int Sequence(int time, int[] frames, int[] durations)
    {
        var t = time % durations.Sum();
        for (var i = 0; i < frames.Length; i++) { if (t < durations[i]) return frames[i]; t -= durations[i]; }
        return frames[0];
    }
}
