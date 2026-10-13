using System.Runtime.InteropServices;
using F2L.Windows;

internal static class ExcelSmoke
{
    // Opt-in integration check: a new, blank Excel instance owned entirely by this test.
    internal static async Task RunAsync()
    {
        var type = Type.GetTypeFromProgID("Excel.Application") ?? throw new InvalidOperationException("Desktop Excel is not installed.");
        dynamic excel = Activator.CreateInstance(type)!;
        object? books = null, workbook = null, sheet = null, window = null;
        try
        {
            excel.DisplayAlerts = false;
            excel.AutomationSecurity = 3;
            books = excel.Workbooks;
            workbook = ((dynamic)books).Add();
            sheet = ((dynamic)workbook).ActiveSheet;
            excel.Visible = true;
            window = excel.ActiveWindow;
            ((dynamic)window).Activate();
            await Task.Delay(500);
            // Codex can retain foreground focus during a tool run. Exercise Excel geometry on our
            // own visible window while retaining the production window identity/bounds checks.
            var resolver = new ExcelTargetResolver(capture => NativeDesktop.IsExternal(capture.SourceWindow)
                && NativeDesktop.ClientBounds(capture.SourceWindow) == capture.Bounds);
            foreach (var zoom in new[] { 100, 150, 80 })
            {
                ((dynamic)window).Zoom = zoom;
                await Task.Delay(150);
                var capture = Snapshot(window);
                var a = await resolver.ResolveAsync(capture, CellReference.Parse("A1")!, CancellationToken.None);
                var b = await resolver.ResolveAsync(capture, CellReference.Parse("B1")!, CancellationToken.None);
                if (!a.Verified || !b.Verified || a.Bounds!.Value.Right > b.Bounds!.Value.Left + 2)
                    throw new InvalidOperationException($"Excel {zoom}%: A1={a.Message}; B1={b.Message}");
                Console.WriteLine($"Excel {zoom}%: A1 and B1 independently verified; separate adjacent rectangles.");
            }
            ((dynamic)window).ScrollColumn = 3;
            await Task.Delay(150);
            var hidden = await resolver.ResolveAsync(Snapshot(window), CellReference.Parse("A1")!, CancellationToken.None);
            if (hidden.Verified) throw new InvalidOperationException("Offscreen A1 was incorrectly highlighted.");
            Console.WriteLine("Excel scrolling: offscreen A1 is rejected.");
            ((dynamic)window).ScrollColumn = 1;
            ((dynamic)window).SplitColumn = 1;
            ((dynamic)window).SplitRow = 1;
            ((dynamic)window).FreezePanes = true;
            await Task.Delay(150);
            var frozen = await resolver.ResolveAsync(Snapshot(window), CellReference.Parse("A1")!, CancellationToken.None);
            if (!frozen.Verified) throw new InvalidOperationException("Frozen A1: " + frozen.Message);
            Console.WriteLine("Excel frozen panes: A1 verified.");
            var beforeMove = Snapshot(window);
            ((dynamic)window).Left = Convert.ToDouble(((dynamic)window).Left) + 24;
            ((dynamic)window).Top = Convert.ToDouble(((dynamic)window).Top) + 18;
            await Task.Delay(200);
            var afterMove = Snapshot(window);
            var moved = await resolver.ResolveAsync(afterMove, CellReference.Parse("A1")!, CancellationToken.None);
            if (!moved.Verified || Math.Abs((moved.Bounds!.Value.X - frozen.Bounds!.Value.X) - (afterMove.ScreenX - beforeMove.ScreenX)) > 2 ||
                Math.Abs((moved.Bounds.Value.Y - frozen.Bounds.Value.Y) - (afterMove.ScreenY - beforeMove.ScreenY)) > 2)
                throw new InvalidOperationException("Excel window movement didn't produce matching cell movement.");
            Console.WriteLine("Excel window movement: A1 geometry follows the window's new screen position.");
        }
        finally
        {
            if (workbook is not null) ((dynamic)workbook).Close(false);
            excel.Quit();
            foreach (var obj in new[] { window, sheet, workbook, books, (object)excel })
                if (obj is not null && Marshal.IsComObject(obj)) Marshal.ReleaseComObject(obj);
        }
    }

    private static CapturedScreen Snapshot(dynamic window)
    {
        var hwnd = new IntPtr(Convert.ToInt64(window.Hwnd));
        var bounds = NativeDesktop.ClientBounds(hwnd);
        NativeDesktop.GetWindowThreadProcessId(hwnd, out var process);
        return new([], (int)bounds.X, (int)bounds.Y, (int)bounds.Width, (int)bounds.Height,
            NativeDesktop.GetDpiForWindow(hwnd), hwnd, process);
    }
}
