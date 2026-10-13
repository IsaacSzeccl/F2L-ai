using System.Windows;

namespace F2L.Windows;

internal enum PointingDirection { None, Left, Right, Up, Down }
internal sealed record CompanionSpot(Rect Bounds, PointingDirection Direction);

internal static class CompanionPlacement
{
    internal static Rect ProtectedArea(Rect target, double scale)
    {
        target.Inflate(30 * scale, 24 * scale);
        return target;
    }

    internal static CompanionSpot? Choose(Rect target, Rect work, Size size, Rect panel, Point cursor, double scale, Rect? previous = null)
    {
        if (!TargetGeometry.IsUsable(target) || size.Width <= 0 || size.Height <= 0) return null;
        var safe = ProtectedArea(target, scale);
        var gap = 12 * scale;
        var center = new Point(target.Left + target.Width / 2, target.Top + target.Height / 2);
        var candidates = new List<CompanionSpot>();
        void Add(double x, double y, PointingDirection direction)
        {
            var bounds = new Rect(x, y, size.Width, size.Height);
            if (work.Contains(bounds) && !bounds.IntersectsWith(safe) && (panel.IsEmpty || !bounds.IntersectsWith(panel)))
                candidates.Add(new(bounds, direction));
        }
        // Favour a side so the learner can continue working along the current row.
        foreach (var y in new[] { center.Y - size.Height / 2, safe.Top, safe.Bottom - size.Height })
        {
            Add(safe.Right + gap, Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - size.Height)), PointingDirection.Left);
            Add(safe.Left - gap - size.Width, Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - size.Height)), PointingDirection.Right);
        }
        foreach (var x in new[] { center.X - size.Width / 2, safe.Left, safe.Right - size.Width })
        {
            Add(Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - size.Width)), safe.Bottom + gap, PointingDirection.Up);
            Add(Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - size.Width)), safe.Top - gap - size.Height, PointingDirection.Down);
        }
        return candidates.OrderBy(spot =>
        {
            var c = new Point(spot.Bounds.Left + size.Width / 2, spot.Bounds.Top + size.Height / 2);
            var score = (c - center).Length;
            var pointerSpace = spot.Bounds; pointerSpace.Inflate(40 * scale, 40 * scale);
            if (pointerSpace.Contains(cursor)) score += 300 * scale;
            if (previous is { } old) score += (spot.Bounds.TopLeft - old.TopLeft).Length * 0.35;
            if (spot.Direction is PointingDirection.Up or PointingDirection.Down) score += 25 * scale;
            return score;
        }).FirstOrDefault();
    }

    internal static bool ShouldYield(Rect sprite, Rect protectedTarget, Point cursor, Rect caret, double scale)
    {
        var pointerSpace = sprite; pointerSpace.Inflate(28 * scale, 28 * scale);
        if (pointerSpace.Contains(cursor) || sprite.IntersectsWith(protectedTarget)) return true;
        if (caret.IsEmpty) return false;
        caret.Inflate(40 * scale, 24 * scale);
        return sprite.IntersectsWith(caret);
    }
}
