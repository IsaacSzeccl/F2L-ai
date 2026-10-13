using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace F2L.Windows;

internal interface IScreenCaptureService : IDisposable
{
    void StartTracking();
    void RememberForeground();
    ForegroundApp? GetTarget();
    void PrepareTarget(ForegroundApp target);
    CapturedScreen CaptureAppJpeg(ForegroundApp target);
}

/// <summary>Captures the remembered external app's client area. The caller hides F2L first.</summary>
internal sealed class ScreenCaptureService : IScreenCaptureService
{
    private readonly ForegroundAppTracker _apps = new();
    private const uint SourceCopy = 0x00CC0020;
    private const uint CaptureLayeredWindows = 0x40000000;
    private const int MaxImageSide = 1800;

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr window, out NativeRect rect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(IntPtr window, ref NativeRect point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetDC(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateCompatibleDC(IntPtr deviceContext);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr deviceContext, int width, int height);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr SelectObject(IntPtr deviceContext, IntPtr graphicsObject);

    [DllImport("gdi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BitBlt(
        IntPtr destination, int x, int y, int width, int height,
        IntPtr source, int sourceX, int sourceY, uint operation);

    [DllImport("gdi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr graphicsObject);

    [DllImport("gdi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(IntPtr deviceContext);

    public void StartTracking() => _apps.Start();
    public void RememberForeground() => _apps.RememberForeground();
    public ForegroundApp? GetTarget() => _apps.GetTarget();

    public void PrepareTarget(ForegroundApp target)
    {
        if (!NativeDesktop.IsCaptureTargetValid(target))
            throw new ScreenCaptureException("The app you were using was closed or minimised. Open it again to share its screen.");
        NativeDesktop.SetForegroundWindow(target.Window);
    }

    public CapturedScreen CaptureAppJpeg(ForegroundApp target)
    {
        var window = target.Window;
        if (!NativeDesktop.IsCaptureTargetValid(target))
            throw new ScreenCaptureException("The app you were using was closed or minimised. Open it again to share its screen.");
        // Pin the request to one window. Never replace it with Pip or a different app midway.
        var foreground = NativeDesktop.GetForegroundWindow();
        if (NativeDesktop.IsExternal(foreground) && NativeDesktop.GetAncestor(foreground, 2) != window)
            throw new ScreenCaptureException("The active app changed while I was preparing the screen. Your question can still be sent without an image.");
        GetWindowThreadProcessId(window, out var processId);
        if (processId != target.Process)
            throw new ScreenCaptureException("That app window is no longer available. Your question can still be sent without an image.");

        if (!GetClientRect(window, out var client))
            throw new ScreenCaptureException("I couldn't read the open app window. Bring it to the front and try again.");

        var width = client.Right - client.Left;
        var height = client.Bottom - client.Top;
        if (width < 120 || height < 100 || width > 16_384 || height > 16_384)
            throw new ScreenCaptureException("The active window is too small or unavailable. Open the app you want help with and try again.");

        if (!ClientToScreen(window, ref client))
            throw new ScreenCaptureException("I couldn't locate the open app on your screen. Bring it to the front and try again.");

        var screenDc = GetDC(IntPtr.Zero);
        if (screenDc == IntPtr.Zero) throw NativeCaptureError();

        var memoryDc = IntPtr.Zero;
        var bitmap = IntPtr.Zero;
        var oldBitmap = IntPtr.Zero;
        try
        {
            memoryDc = CreateCompatibleDC(screenDc);
            if (memoryDc == IntPtr.Zero) throw NativeCaptureError();
            bitmap = CreateCompatibleBitmap(screenDc, width, height);
            if (bitmap == IntPtr.Zero) throw NativeCaptureError();
            oldBitmap = SelectObject(memoryDc, bitmap);
            if (oldBitmap == IntPtr.Zero || oldBitmap == new IntPtr(-1)) throw NativeCaptureError();

            if (!BitBlt(memoryDc, 0, 0, width, height, screenDc, client.Left, client.Top, SourceCopy | CaptureLayeredWindows))
                throw NativeCaptureError();

            var source = Imaging.CreateBitmapSourceFromHBitmap(bitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            BitmapSource image = source;
            var scale = Math.Min(1.0, (double)MaxImageSide / Math.Max(source.PixelWidth, source.PixelHeight));
            if (scale < 1.0)
            {
                var resized = new TransformedBitmap(source, new ScaleTransform(scale, scale));
                resized.Freeze();
                image = resized;
            }

            var encoder = new JpegBitmapEncoder { QualityLevel = 82 };
            encoder.Frames.Add(BitmapFrame.Create(image));
            using var output = new MemoryStream();
            encoder.Save(output);
            var dpi = GetDpiForWindow(window);
            return new CapturedScreen(output.ToArray(), client.Left, client.Top, width, height, dpi == 0 ? 96 : dpi, window, processId);
        }
        finally
        {
            if (oldBitmap != IntPtr.Zero && oldBitmap != new IntPtr(-1) && memoryDc != IntPtr.Zero)
                SelectObject(memoryDc, oldBitmap);
            if (bitmap != IntPtr.Zero) DeleteObject(bitmap);
            if (memoryDc != IntPtr.Zero) DeleteDC(memoryDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    public void Dispose() => _apps.Dispose();

    private static ScreenCaptureException NativeCaptureError()
    {
        var error = new Win32Exception(Marshal.GetLastWin32Error());
        return new ScreenCaptureException($"F2L couldn't take a snapshot of the active app ({error.NativeErrorCode}). Try again.");
    }
}

internal sealed record CapturedScreen(byte[] JpegBytes, int ScreenX, int ScreenY, int PixelWidth, int PixelHeight, uint Dpi,
    IntPtr SourceWindow, uint SourceProcess)
{
    internal Rect Bounds => new(ScreenX, ScreenY, PixelWidth, PixelHeight);
}

internal sealed class ScreenCaptureException(string message) : Exception(message);
