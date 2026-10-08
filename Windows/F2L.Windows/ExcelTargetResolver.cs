using System.Runtime.InteropServices;
using System.Windows;

namespace F2L.Windows;

internal sealed record ExcelTargetResult(Rect? Bounds, string Message, string? Sheet = null)
{
    internal bool Verified => Bounds is { } bounds && TargetGeometry.IsUsable(bounds);
}

/// <summary>Reads geometry only. Never selects, edits, scrolls, activates, or saves a workbook.</summary>
internal sealed class ExcelTargetResolver(Func<CapturedScreen, bool>? snapshotValidator = null)
{
    private readonly SemaphoreSlim _worker = new(1, 1);
    private readonly Func<CapturedScreen, bool> _snapshotValidator = snapshotValidator ?? NativeDesktop.IsSnapshotCurrent;

    internal async Task<ExcelTargetResult> ResolveAsync(CapturedScreen capture, CellReference cell, CancellationToken cancellationToken)
    {
        if (NativeDesktop.ClassName(capture.SourceWindow) != "XLMAIN")
            return new(null, $"I can verify {cell.Address} in desktop Excel. For Excel in a browser, I won't guess a cell's position.");
        if (!await _worker.WaitAsync(0, cancellationToken))
            return new(null, "Excel is still responding. Try again after closing any open Excel dialog.");

        var completion = new TaskCompletionSource<ExcelTargetResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { completion.TrySetResult(Resolve(capture, cell)); }
            catch (Exception) { completion.TrySetResult(new(null, $"I couldn't verify {cell.Address}. Make the cell visible in desktop Excel and finish editing it, then ask again.")); }
            finally { _worker.Release(); }
        }) { IsBackground = true, Name = "F2L Excel geometry" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        try { return await completion.Task.WaitAsync(TimeSpan.FromSeconds(3), cancellationToken); }
        catch (TimeoutException) { return new(null, "Excel didn't return a cell position in time. I haven't drawn a circle."); }
    }

    internal async Task<ExcelContext?> ReadSelectionAsync(ForegroundApp app, CancellationToken token)
    {
        if (NativeDesktop.ClassName(app.Window) != "XLMAIN" || !NativeDesktop.IsCaptureTargetValid(app)) return null;
        if (!await _worker.WaitAsync(0, token)) return null;
        var completion = new TaskCompletionSource<ExcelContext?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                ExcelContext? context = null;
                var handles = new List<IntPtr>();
                NativeDesktop.EnumChildWindows(app.Window, (handle, _) =>
                {
                    if (NativeDesktop.ClassName(handle) == "EXCEL7" && NativeDesktop.IsWindowVisible(handle)) handles.Add(handle);
                    return true;
                }, IntPtr.Zero);
                foreach (var handle in handles)
                {
                    using var objects = new ComObjects();
                    var dispatch = new Guid("00020400-0000-0000-C000-000000000046");
                    if (AccessibleObjectFromWindow(handle, 0xFFFFFFF0, ref dispatch, out var native) != 0 || native is null) continue;
                    dynamic window = objects.Add(native);
                    if (NativeDesktop.GetAncestor(new IntPtr(Convert.ToInt64(window.Hwnd)), 2) != NativeDesktop.GetAncestor(app.Window, 2)) continue;
                    dynamic sheet = objects.Add(window.ActiveSheet);
                    dynamic selection = objects.Add(window.Selection);
                    dynamic areas = objects.Add(selection.Areas);
                    dynamic active = objects.Add(window.ActiveCell);
                    var addresses = new List<string>();
                    for (var i = 1; i <= Convert.ToInt32(areas.Count); i++)
                    {
                        dynamic area = objects.Add(areas.Item[i]);
                        addresses.Add(Convert.ToString(area.Address[true, true, 1, false, Type.Missing]) ?? "");
                    }
                    context = ExcelContext.Parse(Convert.ToString(sheet.Name) ?? "", string.Join(",", addresses),
                        Convert.ToString(active.Address[true, true, 1, false, Type.Missing]) ?? "");
                    break;
                }
                completion.TrySetResult(NativeDesktop.IsCaptureTargetValid(app) ? context : null);
            }
            catch { completion.TrySetResult(null); }
            finally { _worker.Release(); }
        }) { IsBackground = true, Name = "F2L Excel selection" };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
        try { return await completion.Task.WaitAsync(TimeSpan.FromSeconds(3), token); }
        catch (TimeoutException) { return null; }
    }

    private ExcelTargetResult Resolve(CapturedScreen capture, CellReference cell)
    {
        if (!_snapshotValidator(capture)) return new(null, "The app window changed. Ask again with Excel visible.");
        var documentWindows = new List<IntPtr>();
        NativeDesktop.EnumChildWindows(capture.SourceWindow, (window, _) =>
        {
            if (NativeDesktop.ClassName(window) == "EXCEL7" && NativeDesktop.IsWindowVisible(window)) documentWindows.Add(window);
            return true;
        }, IntPtr.Zero);

        foreach (var handle in documentWindows)
        {
            using var objects = new ComObjects();
            var dispatch = new Guid("00020400-0000-0000-C000-000000000046");
            if (AccessibleObjectFromWindow(handle, 0xFFFFFFF0, ref dispatch, out var native) != 0 || native is null) continue;
            dynamic window = objects.Add(native);
            var actualRoot = NativeDesktop.GetAncestor(new IntPtr(Convert.ToInt64(window.Hwnd)), 2);
            if (actualRoot != NativeDesktop.GetAncestor(capture.SourceWindow, 2)) continue;
            dynamic sheet = objects.Add(window.ActiveSheet);
            dynamic cellRange = objects.Add(sheet.Range[cell.Address]);
            dynamic range = objects.Add(cellRange.MergeArea);
            dynamic panes = objects.Add(window.Panes);
            var paneCount = Convert.ToInt32(panes.Count);
            for (var index = 1; index <= paneCount; index++)
            {
                dynamic pane = objects.Add(panes.Item[index]);
                dynamic visible = objects.Add(pane.VisibleRange);
                dynamic rows = objects.Add(visible.Rows);
                dynamic columns = objects.Add(visible.Columns);
                var firstRow = Convert.ToInt32(visible.Row);
                var firstColumn = Convert.ToInt32(visible.Column);
                if (cell.Row < firstRow || cell.Row >= firstRow + Convert.ToInt32(rows.Count) ||
                    cell.Column < firstColumn || cell.Column >= firstColumn + Convert.ToInt32(columns.Count)) continue;

                var left = Convert.ToDouble(range.Left);
                var top = Convert.ToDouble(range.Top);
                var width = Convert.ToDouble(range.Width);
                var height = Convert.ToDouble(range.Height);
                if (width <= 0 || height <= 0) continue;
                var x1 = Convert.ToInt32(pane.PointsToScreenPixelsX((int)Math.Round(left)));
                var y1 = Convert.ToInt32(pane.PointsToScreenPixelsY((int)Math.Round(top)));
                var x2 = Convert.ToInt32(pane.PointsToScreenPixelsX((int)Math.Round(left + width)));
                var y2 = Convert.ToInt32(pane.PointsToScreenPixelsY((int)Math.Round(top + height)));
                if (x2 <= x1 || y2 <= y1) continue;
                var bounds = new Rect(x1, y1, x2 - x1, y2 - y1);
                if (!capture.Bounds.Contains(bounds) || !TargetGeometry.IsUsable(bounds)) continue;

                // Ask Excel what is at all three sample points: an A1 request must never accept B1.
                var insetX = Math.Min(3, bounds.Width / 4);
                var insetY = Math.Min(3, bounds.Height / 4);
                if (!VerifyPoint(window, cell, bounds.Left + insetX, bounds.Top + insetY, objects) ||
                    !VerifyPoint(window, cell, bounds.Left + bounds.Width / 2, bounds.Top + bounds.Height / 2, objects) ||
                    !VerifyPoint(window, cell, bounds.Right - insetX, bounds.Bottom - insetY, objects)) continue;
                var sheetName = Convert.ToString(sheet.Name) ?? "worksheet";
                return new(bounds, $"Verified {cell.Address} in {sheetName}", sheetName);
            }
        }
        return new(null, $"I couldn't verify a fully visible {cell.Address}. Bring that cell into view in desktop Excel and ask again. I haven't circled a neighbouring cell.");
    }

    private static bool VerifyPoint(dynamic window, CellReference requested, double x, double y, ComObjects objects)
    {
        try
        {
            object? raw = window.RangeFromPoint((int)Math.Round(x), (int)Math.Round(y));
            if (raw is null) return false;
            dynamic hit = objects.Add(raw);
            dynamic area = objects.Add(hit.MergeArea);
            dynamic rows = objects.Add(area.Rows);
            dynamic columns = objects.Add(area.Columns);
            var row = Convert.ToInt32(area.Row);
            var column = Convert.ToInt32(area.Column);
            return requested.Row >= row && requested.Row < row + Convert.ToInt32(rows.Count) &&
                requested.Column >= column && requested.Column < column + Convert.ToInt32(columns.Count);
        }
        catch { return false; }
    }

    private sealed class ComObjects : IDisposable
    {
        private readonly List<object> _items = [];
        internal dynamic Add(object value) { if (Marshal.IsComObject(value)) _items.Add(value); return value; }
        public void Dispose()
        {
            for (var i = _items.Count - 1; i >= 0; i--)
                try { Marshal.ReleaseComObject(_items[i]); } catch (InvalidComObjectException) { }
        }
    }

    [DllImport("oleacc.dll")]
    private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid interfaceId,
        [MarshalAs(UnmanagedType.IDispatch)] out object? result);
}
