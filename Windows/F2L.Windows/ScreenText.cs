using System.Windows;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace F2L.Windows;

/// <summary>A word read from the screenshot on this computer (Windows OCR), in physical screen pixels.</summary>
internal sealed record ScreenWord(string Text, Rect Frame);

/// <summary>Finds buttons and Excel cells by reading the screen. Mirrors Sources/CoachCore/ScreenText.swift and
/// Sources/F2L/ScreenReading.swift.</summary>
internal static class ScreenText
{
    /// <summary>Lines of words read from <paramref name="capture"/>'s picture on this PC. Nothing is sent anywhere.</summary>
    internal static async Task<IReadOnlyList<IReadOnlyList<ScreenWord>>> ReadAsync(CapturedScreen capture)
    {
        try
        {
            if (capture.JpegBytes.Length == 0 || OcrEngine.TryCreateFromUserProfileLanguages() is not { } engine) return [];
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream))
            {
                writer.WriteBytes(capture.JpegBytes);
                await writer.StoreAsync();
                writer.DetachStream();
            }
            stream.Seek(0);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var result = await engine.RecognizeAsync(bitmap);
            double sx = capture.PixelWidth / (double)decoder.PixelWidth, sy = capture.PixelHeight / (double)decoder.PixelHeight;
            return result.Lines.Select(line => (IReadOnlyList<ScreenWord>)line.Words.Select(word => new ScreenWord(word.Text,
                new Rect(capture.ScreenX + word.BoundingRect.X * sx, capture.ScreenY + word.BoundingRect.Y * sy,
                    word.BoundingRect.Width * sx, word.BoundingRect.Height * sy))).OrderBy(word => word.Frame.X).ToArray()).ToArray();
        }
        catch (Exception) { return []; }
    }

    /// <summary>Every run of one to four neighbouring words on a line, as a control candidate.</summary>
    internal static IReadOnlyList<ControlCandidate> Candidates(IReadOnlyList<IReadOnlyList<ScreenWord>> lines)
    {
        var result = new List<ControlCandidate>();
        foreach (var line in lines)
            for (var start = 0; start < line.Count; start++)
            {
                var frame = Rect.Empty;
                var words = new List<string>();
                for (var end = start; end < Math.Min(line.Count, start + 4); end++)
                {
                    // A big gap means the next word belongs to another control.
                    if (end > start && line[end].Frame.Left - line[end - 1].Frame.Right > Math.Max(14, line[end].Frame.Height * 1.2)) break;
                    frame.Union(line[end].Frame);
                    words.Add(line[end].Text);
                    result.Add(new ControlCandidate(frame, string.Join(' ', words)));
                }
            }
        return result;
    }

    /// <summary>Where <paramref name="address"/> (a cell or range) is on screen, from Excel's column letters and row
    /// numbers read off the screen. Null when the needed headings aren't visible.</summary>
    internal static Rect? ExcelCell(string address, IEnumerable<ScreenWord> words)
    {
        var parts = address.ToUpperInvariant().Replace("$", "").Split(':');
        if (parts.Length is < 1 or > 2 || CellReference.Parse(parts[0]) is not { } first) return null;
        if ((parts.Length == 2 ? CellReference.Parse(parts[1]) : first) is not { } last) return null;
        var all = words.ToArray();
        if (ColumnHeadings(all) is not { } columns || RowHeadings(all) is not { } rows) return null;
        if (Span(Math.Min(first.Column, last.Column), columns) is not { } left || Span(Math.Max(first.Column, last.Column), columns) is not { } right ||
            Span(Math.Min(first.Row, last.Row), rows) is not { } top || Span(Math.Max(first.Row, last.Row), rows) is not { } bottom) return null;
        return new Rect(left.Low, top.Low, right.High - left.Low, bottom.High - top.Low);
    }

    private static IReadOnlyList<(int Index, double Center)>? ColumnHeadings(ScreenWord[] words) => Headings(words.Select(word =>
    {
        var text = word.Text.Trim().ToUpperInvariant();
        return text.Length is >= 1 and <= 3 && text.All(c => c is >= 'A' and <= 'Z') && CellReference.Parse(text + "1") is { } cell
            ? (cell.Column, word) : ((int, ScreenWord)?)null;
    }).OfType<(int, ScreenWord)>(), word => word.Frame.Y + word.Frame.Height / 2, word => word.Frame.X + word.Frame.Width / 2);

    private static IReadOnlyList<(int Index, double Center)>? RowHeadings(ScreenWord[] words) => Headings(words.Select(word =>
        int.TryParse(word.Text.Trim(), out var row) && row is >= 1 and <= 1_048_576 ? (row, word) : ((int, ScreenWord)?)null)
        .OfType<(int, ScreenWord)>(), word => word.Frame.X + word.Frame.Width / 2, word => word.Frame.Y + word.Frame.Height / 2);

    /// <summary>Groups items on the same band (within 6 units), then finds the evenly spaced headings most pairs agree
    /// on; missing ones are fine. At least three, so stray letters or numbers in cells don't count.</summary>
    private static IReadOnlyList<(int Index, double Center)>? Headings(IEnumerable<(int Index, ScreenWord Word)> items,
        Func<ScreenWord, double> band, Func<ScreenWord, double> position)
    {
        var groups = new List<List<(int Index, double Center)>>();
        var bands = new List<double>();
        foreach (var item in items.OrderBy(item => band(item.Word)))
        {
            if (bands.Count > 0 && Math.Abs(bands[^1] - band(item.Word)) <= 6) groups[^1].Add((item.Index, position(item.Word)));
            else { groups.Add([(item.Index, position(item.Word))]); bands.Add(band(item.Word)); }
        }
        IReadOnlyList<(int Index, double Center)> best = [];
        foreach (var group in groups.Where(group => group.Count >= 3))
            foreach (var a in group)
                foreach (var b in group.Where(b => b.Index > a.Index))
                {
                    var step = (b.Center - a.Center) / (b.Index - a.Index);
                    if (step <= 4) continue;
                    var offsets = group.Select(item => item.Center - item.Index * step).OrderBy(offset => offset).ToArray();
                    var offset = offsets[offsets.Length / 2];
                    var fits = group.Where(item => Math.Abs(item.Center - (offset + item.Index * step)) <= step * 0.3)
                        .OrderBy(item => item.Index).DistinctBy(item => item.Index).ToArray();
                    if (fits.Length > best.Count) best = fits;
                }
        return best.Count >= 3 ? best : null;
    }

    /// <summary>The extent of heading <paramref name="index"/>: halfway to its neighbours' centres.</summary>
    private static (double Low, double High)? Span(int index, IReadOnlyList<(int Index, double Center)> headings)
    {
        if (headings.Count < 2) return null;
        var (first, last) = (headings[0], headings[^1]);
        var step = (last.Center - first.Center) / (last.Index - first.Index);
        if (step <= 0 || index < first.Index - 1 || index > last.Index + 1) return null;
        double Center(int i)
        {
            foreach (var heading in headings) if (heading.Index == i) return heading.Center;
            return first.Center + (i - first.Index) * step;
        }
        var center = Center(index);
        var low = (center + Center(index - 1)) / 2; var high = (center + Center(index + 1)) / 2;
        return (Math.Min(low, high), Math.Max(low, high));
    }
}
