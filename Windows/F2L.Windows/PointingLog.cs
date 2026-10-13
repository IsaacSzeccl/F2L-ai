using System.IO;
using System.Text.Json;
using System.Windows;

namespace F2L.Windows;

/// <summary>A local record of how Pip decided where to point, so a wrong circle can be debugged from facts.
/// %LOCALAPPDATA%\F2L\pointing.log, no pictures, trimmed to its last 200 KB. Mirrors PointingDiagnostics.swift.</summary>
internal static class PointingLog
{
    private static readonly string Path = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "F2L", "pointing.log");

    private static object? Box(Rect? rect) => rect is { } r ? new { x = r.X, y = r.Y, w = r.Width, h = r.Height } : null;

    internal static void Record(ScreenTarget target, string source, Rect? drawn, Rect? modelBox = null)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var line = JsonSerializer.Serialize(new { time = DateTimeOffset.Now, label = target.Label, cell = target.Cell, source, drawn = Box(drawn), modelBox = Box(modelBox) });
            File.AppendAllText(Path, line + "\n");
            if (new FileInfo(Path).Length > 200_000) File.WriteAllText(Path, File.ReadAllText(Path)[^150_000..]);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
