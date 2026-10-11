using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media.Imaging;

namespace F2L.Windows;

/// <summary>A second, zoomed look for a place F2L couldn't confirm from the screen's words or the app's controls: crop the
/// window around the AI's first guess (or take the whole window) and ask the same AI where the control is in that crop.
/// Mirrors Sources/CoachCore/ZoomLocate.swift.</summary>
internal static class ZoomLocate
{
    internal const string SystemPrompt = """
        You find one control in a cropped screenshot of an app. Return only a JSON object.
        If the named control is clearly visible, return {"found":true,"left":L,"top":T,"right":R,"bottom":B} with integers
        from 0 to 1000 that are thousandths of this image and tightly surround the control.
        Otherwise return {"found":false}. Never guess.
        """;

    internal static string Question(string label, string app) =>
        $"Find the \"{label}\" control (a button, tab, icon, menu item or field) in this part of the {app} window. Return JSON.";

    /// <summary>Around the first guess: six times its size, at least 420 × 280 (in the same units as the window), inside the window.</summary>
    internal static readonly Size Minimum = new(420, 280);

    internal static Rect Crop(Rect? estimate, Rect window)
    {
        if (estimate is not { IsEmpty: false } guess || window.IsEmpty) return window;
        var width = Math.Min(window.Width, Math.Max(Minimum.Width, guess.Width * 6));
        var height = Math.Min(window.Height, Math.Max(Minimum.Height, guess.Height * 6));
        var x = Math.Min(Math.Max(guess.X + guess.Width / 2 - width / 2, window.Left), window.Right - width);
        var y = Math.Min(Math.Max(guess.Y + guess.Height / 2 - height / 2, window.Top), window.Bottom - height);
        return new(x, y, width, height);
    }

    /// <summary>The crop in the picture's pixels, for a picture of <paramref name="window"/> that is <paramref name="pixels"/> big.</summary>
    internal static Int32Rect PixelRect(Rect crop, Rect window, Size pixels)
    {
        if (window.Width <= 0 || window.Height <= 0) return Int32Rect.Empty;
        double sx = pixels.Width / window.Width, sy = pixels.Height / window.Height;
        var left = Math.Max(0, (int)Math.Floor((crop.Left - window.Left) * sx));
        var top = Math.Max(0, (int)Math.Floor((crop.Top - window.Top) * sy));
        var right = Math.Min((int)pixels.Width, (int)Math.Ceiling((crop.Right - window.Left) * sx));
        var bottom = Math.Min((int)pixels.Height, (int)Math.Ceiling((crop.Bottom - window.Top) * sy));
        return right > left && bottom > top ? new(left, top, right - left, bottom - top) : Int32Rect.Empty;
    }

    /// <summary>The part of a window picture that covers <paramref name="crop"/>, as a sharper JPEG.</summary>
    internal static byte[]? CropJpeg(byte[] jpeg, Rect window, Rect crop)
    {
        try
        {
            using var stream = new MemoryStream(jpeg);
            var frame = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
            var rect = PixelRect(crop, window, new Size(frame.PixelWidth, frame.PixelHeight));
            if (rect.Width < 8 || rect.Height < 8) return null;
            var encoder = new JpegBitmapEncoder { QualityLevel = 90 };
            encoder.Frames.Add(BitmapFrame.Create(new CroppedBitmap(frame, rect)));
            using var output = new MemoryStream();
            encoder.Save(output);
            return output.ToArray();
        }
        catch (Exception error) when (error is NotSupportedException or InvalidOperationException or ArgumentException or IOException) { return null; }
    }

    /// <summary>The control's place from the reply, or null when it wasn't found or the box makes no sense.</summary>
    internal static Rect? Parse(string text, Rect crop)
    {
        var clean = text.Trim();
        if (clean.StartsWith("```")) clean = CoachClient.FenceEnd().Replace(CoachClient.FenceStart().Replace(clean, ""), "").Trim();
        try
        {
            using var json = JsonDocument.Parse(clean);
            var root = json.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("found", out var found) || found.ValueKind != JsonValueKind.True) return null;
            double? Value(string key) => root.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.Number && item.TryGetDouble(out var number)
                && number is >= 0 and <= 1000 ? number / 1000 : null;
            if (Value("left") is not { } left || Value("top") is not { } top || Value("right") is not { } right || Value("bottom") is not { } bottom
                || right <= left || bottom <= top) return null;
            var box = new Rect(crop.X + left * crop.Width, crop.Y + top * crop.Height, (right - left) * crop.Width, (bottom - top) * crop.Height);
            // A control is small: a box over most of the crop means the model didn't really find it.
            return box.Width >= 4 && box.Height >= 4 && box.Width <= crop.Width * 0.8 && box.Height <= crop.Height * 0.8 ? box : null;
        }
        catch (JsonException) { return null; }
    }
}
