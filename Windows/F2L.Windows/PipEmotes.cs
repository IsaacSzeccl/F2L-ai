using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace F2L.Windows;

/// <summary>Pip's own emotes, used where an app would otherwise show a system emoji. The PNGs are exported from the
/// Mac app's PipEmote (`F2L --export-emotes`), so both apps show the same pictures.</summary>
internal enum PipEmote { Hello, Happy, Cheer, Thinking, Curious, Focused }

internal static class PipEmotes
{
    private static readonly Dictionary<PipEmote, ImageSource> Cache = [];

    internal static ImageSource? Image(PipEmote emote)
    {
        if (Cache.TryGetValue(emote, out var cached)) return cached;
        try
        {
            var image = new BitmapImage(new Uri($"pack://application:,,,/F2L.Windows;component/Assets/Pip/Emotes/{emote.ToString().ToLowerInvariant()}.png"));
            image.Freeze();
            Cache[emote] = image;
            return image;
        }
        catch (Exception) { return null; }
    }
}
