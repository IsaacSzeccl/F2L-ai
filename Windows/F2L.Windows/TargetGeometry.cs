using System.Windows;

namespace F2L.Windows;

internal static class TargetGeometry
{
    internal static Rect FromScreenshot(CapturedScreen capture, ScreenTarget target) => new(
        capture.ScreenX + target.Left * capture.PixelWidth / 1000d,
        capture.ScreenY + target.Top * capture.PixelHeight / 1000d,
        (target.Right - target.Left) * capture.PixelWidth / 1000d,
        (target.Bottom - target.Top) * capture.PixelHeight / 1000d);

    // Keep the real cell size. Enlarging a short row to 42 DIPs can outline neighbouring cells.
    internal static Rect OverlayBounds(Rect targetPixels, double scale, double padding = 8)
    {
        var result = targetPixels;
        result.Inflate(padding * scale, padding * scale);
        return result;
    }

    internal static bool IsUsable(Rect rect) => !rect.IsEmpty && double.IsFinite(rect.X) && double.IsFinite(rect.Y) &&
        double.IsFinite(rect.Width) && double.IsFinite(rect.Height) && rect.Width >= 2 && rect.Height >= 2;
}
