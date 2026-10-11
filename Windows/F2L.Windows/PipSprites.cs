using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace F2L.Windows;

internal sealed record PipSprite(BitmapSource Image, double Width, double Height);

internal static class PipSprites
{
    private static readonly Lazy<PipSprite[]> ExpressionFrames = new(() => Load("expressions"));
    private static readonly Lazy<PipSprite[]> DirectionFrames = new(() => Load("directions"));
    private static readonly Lazy<PipSprite[]> PlayfulFrames = new(() => Load("playful"));
    internal static PipSprite[] Expressions => ExpressionFrames.Value;
    internal static PipSprite[] Directions => DirectionFrames.Value;
    internal static PipSprite[] Playful => PlayfulFrames.Value;

    private static PipSprite[] Load(string name)
    {
        var atlas = new BitmapImage(new Uri($"pack://application:,,,/F2L.Windows;component/Assets/Pip/{name}.png"));
        atlas.Freeze();
        // Pose rectangles are precomputed in frames.json (scripts/tools/pip_frames.py); scanning the
        // atlas is only the fallback when the manifest is missing or belongs to different artwork.
        var bounds = ManifestFrames(name, atlas) ?? FindFrames(atlas);
        var scale = 288d / (atlas.PixelWidth / 4d);
        return bounds.Select(rect =>
        {
            var image = new CroppedBitmap(atlas, rect); image.Freeze();
            return new PipSprite(image, rect.Width * scale, rect.Height * scale);
        }).ToArray();
    }

    internal static Int32Rect[]? ManifestFrames(string name, BitmapSource atlas)
    {
        try
        {
            var resource = Application.GetResourceStream(new Uri("pack://application:,,,/F2L.Windows;component/Assets/Pip/frames.json"));
            if (resource is null) return null;
            using var stream = resource.Stream;
            using var document = JsonDocument.Parse(stream);
            var sheet = document.RootElement.GetProperty(name);
            var size = sheet.GetProperty("atlas");
            if (size[0].GetInt32() != atlas.PixelWidth || size[1].GetInt32() != atlas.PixelHeight) return null;
            var frames = sheet.GetProperty("frames").EnumerateArray()
                .Select(f => new Int32Rect(f[0].GetInt32(), f[1].GetInt32(), f[2].GetInt32(), f[3].GetInt32())).ToArray();
            return frames.Length == 16 ? frames : null;
        }
        catch (Exception error) when (error is IOException or JsonException or KeyNotFoundException or InvalidOperationException or IndexOutOfRangeException) { return null; }
    }

    internal static Int32Rect[] FindFrames(BitmapSource atlas)
    {
        var rgba = new FormatConvertedBitmap(atlas, PixelFormats.Bgra32, null, 0);
        var width = rgba.PixelWidth; var height = rgba.PixelHeight;
        var bytes = new byte[width * height * 4]; rgba.CopyPixels(bytes, width * 4, 0);
        var seen = new bool[width * height];
        var queue = new Queue<int>();
        var regions = new List<(int Count, Int32Rect Bounds)>();
        for (var start = 0; start < seen.Length; start++)
        {
            if (seen[start] || bytes[start * 4 + 3] < 48) continue;
            seen[start] = true; queue.Enqueue(start);
            var left = width; var right = 0; var top = height; var bottom = 0; var count = 0;
            while (queue.TryDequeue(out var pixel))
            {
                var x = pixel % width; var y = pixel / width; count++;
                left = Math.Min(left, x); right = Math.Max(right, x); top = Math.Min(top, y); bottom = Math.Max(bottom, y);
                void Visit(int neighbour)
                {
                    if (seen[neighbour] || bytes[neighbour * 4 + 3] < 48) return;
                    seen[neighbour] = true; queue.Enqueue(neighbour);
                }
                if (x > 0) Visit(pixel - 1); if (x + 1 < width) Visit(pixel + 1);
                if (y > 0) Visit(pixel - width); if (y + 1 < height) Visit(pixel + width);
            }
            if (count < width * height / 1000) continue;
            var x0 = Math.Max(0, left - 2); var y0 = Math.Max(0, top - 2);
            regions.Add((count, new(x0, y0, Math.Min(width - 1, right + 2) - x0 + 1, Math.Min(height - 1, bottom + 2) - y0 + 1)));
        }
        var actors = regions.OrderByDescending(r => r.Count).Take(16).Select(r => r.Bounds).OrderBy(r => r.Y + r.Height / 2).ToArray();
        if (actors.Length != 16) throw new InvalidOperationException("Pip's sprite atlas must contain 16 separate transparent poses.");
        return actors.Chunk(4).SelectMany(row => row.OrderBy(r => r.X + r.Width / 2)).ToArray();
    }
}
