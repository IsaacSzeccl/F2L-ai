using System.Windows.Media.Imaging;

namespace F2L.Windows;

/// <summary>F2L's original painted artwork (Assets/Brand and Assets/Illustrations, shared with the Mac app), decoded once
/// at the size it is shown, frozen and reused so animation never decodes on a tick. The masters are 1254 px squares;
/// squares are decoded at most 512 px wide (about 1 MB instead of 6 MB each), and the opening's screen-sized backdrop
/// keeps its full width and can be let go after the opening. Mirrors Sources/F2L/BrandArtwork.swift.</summary>
internal static class BrandArtwork
{
    internal const string Landscape = "Brand/launch-landscape.png";
    private const int SquareLimit = 512;
    private static readonly Dictionary<string, BitmapImage> Cache = [];

    internal static BitmapImage Image(string path)
    {
        if (Cache.TryGetValue(path, out var image)) return image;
        image = new BitmapImage();
        image.BeginInit();
        image.UriSource = new Uri($"pack://application:,,,/F2L.Windows;component/Assets/{path}");
        image.CacheOption = BitmapCacheOption.OnLoad;
        if (path != Landscape) image.DecodePixelWidth = SquareLimit;
        image.EndInit();
        image.Freeze();
        Cache[path] = image;
        return image;
    }

    /// <summary>Lets a picture that is only shown once (the opening's backdrop) be freed.</summary>
    internal static void Forget(string path) => Cache.Remove(path);
}
