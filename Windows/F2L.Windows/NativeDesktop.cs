using System.Runtime.InteropServices;
using System.Text;
using System.Windows;

namespace F2L.Windows;

internal static class NativeDesktop
{
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] internal struct NativePoint { public int X, Y; public NativePoint(int x, int y) { X = x; Y = y; } }
    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out int value, int size);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref NativePoint point);
    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] internal static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(NativePoint point);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public NativeRect Monitor, Work; public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] private struct GuiThreadInfo
    {
        public int Size; public uint Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public NativeRect CaretRect;
    }
    [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    internal delegate bool EnumWindowCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] internal static extern bool EnumChildWindows(IntPtr parent, EnumWindowCallback callback, IntPtr parameter);

    internal static bool IsExternal(IntPtr window)
    {
        if (window == IntPtr.Zero || !IsWindowVisible(window) || IsIconic(window)) return false;
        GetWindowThreadProcessId(window, out var process);
        return process != 0 && process != Environment.ProcessId;
    }

    internal static ForegroundApp? CaptureCandidate(IntPtr window)
    {
        window = GetAncestor(window, 2);
        if (!IsExternal(window) || ClassName(window) is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return null;
        if (DwmGetWindowAttribute(window, 14, out var cloaked, sizeof(int)) == 0 && cloaked != 0) return null;
        var bounds = ClientBounds(window);
        if (bounds.IsEmpty || bounds.Width < 120 || bounds.Height < 100) return null;
        GetWindowThreadProcessId(window, out var process);
        return new(window, process);
    }

    internal static bool IsCaptureTargetValid(ForegroundApp target)
    {
        if (!IsWindow(target.Window)) return false;
        return CaptureCandidate(target.Window) == target;
    }

    internal static string ClassName(IntPtr window)
    {
        var text = new StringBuilder(256);
        GetClassName(window, text, text.Capacity);
        return text.ToString();
    }

    internal static Rect ClientBounds(IntPtr window)
    {
        if (!GetClientRect(window, out var rect)) return Rect.Empty;
        var point = new NativePoint(0, 0);
        if (!ClientToScreen(window, ref point)) return Rect.Empty;
        return new Rect(point.X, point.Y, Math.Max(0, rect.Right - rect.Left), Math.Max(0, rect.Bottom - rect.Top));
    }

    internal static bool IsSnapshotCurrent(CapturedScreen capture)
    {
        return IsSourceCurrent(capture) && ClientBounds(capture.SourceWindow) == capture.Bounds;
    }

    internal static bool IsSourceCurrent(CapturedScreen capture)
    {
        if (!IsExternal(capture.SourceWindow)) return false;
        GetWindowThreadProcessId(capture.SourceWindow, out var process);
        if (process != capture.SourceProcess) return false;
        var foreground = GetForegroundWindow();
        if (IsExternal(foreground) && GetAncestor(foreground, 2) != GetAncestor(capture.SourceWindow, 2)) return false;
        return true;
    }

    internal static CapturedScreen? RefreshGeometry(CapturedScreen capture)
    {
        if (!IsSourceCurrent(capture)) return null;
        var bounds = ClientBounds(capture.SourceWindow);
        if (!TargetGeometry.IsUsable(bounds)) return null;
        return capture with { ScreenX = (int)bounds.X, ScreenY = (int)bounds.Y, PixelWidth = (int)bounds.Width,
            PixelHeight = (int)bounds.Height, Dpi = GetDpiForWindow(capture.SourceWindow) };
    }

    internal static Point CursorPosition => GetCursorPos(out var point) ? new(point.X, point.Y) : new(-100000, -100000);

    internal static Rect WorkAreaAt(Point point)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        var monitor = MonitorFromPoint(new NativePoint((int)point.X, (int)point.Y), 2);
        return GetMonitorInfo(monitor, ref info)
            ? new Rect(info.Work.Left, info.Work.Top, info.Work.Right - info.Work.Left, info.Work.Bottom - info.Work.Top)
            : new Rect(0, 0, SystemParameters.PrimaryScreenWidth, SystemParameters.PrimaryScreenHeight);
    }

    internal static Rect ActiveCaretBounds()
    {
        var info = new GuiThreadInfo { Size = Marshal.SizeOf<GuiThreadInfo>() };
        if (!GetGUIThreadInfo(0, ref info) || info.Caret == IntPtr.Zero || !IsExternal(info.Caret)) return Rect.Empty;
        var point = new NativePoint(info.CaretRect.Left, info.CaretRect.Top);
        if (!ClientToScreen(info.Caret, ref point)) return Rect.Empty;
        return new Rect(point.X, point.Y, Math.Max(2, info.CaretRect.Right - info.CaretRect.Left), Math.Max(2, info.CaretRect.Bottom - info.CaretRect.Top));
    }

    internal static bool PointBelongsToWindow(IntPtr window, Point point)
    {
        var hit = WindowFromPoint(new NativePoint((int)Math.Round(point.X), (int)Math.Round(point.Y)));
        return GetAncestor(hit, 2) == GetAncestor(window, 2);
    }
}
