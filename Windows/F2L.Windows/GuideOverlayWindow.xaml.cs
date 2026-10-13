using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace F2L.Windows;

public partial class GuideOverlayWindow : Window
{
    public GuideOverlayWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            var style = GetWindowLongPtr(handle, -20).ToInt64();
            SetWindowLongPtr(handle, -20, new IntPtr(style | 0x20L | 0x80L | 0x08000000L));
        };
    }

    public void ShowTarget(Rect targetPixels, bool verified)
    {
        if (!TargetGeometry.IsUsable(targetPixels)) return;
        var handle = new WindowInteropHelper(this).EnsureHandle();
        // Place on the target monitor first, then use this overlay's DPI. Global screen origins
        // must stay in physical pixels; dividing them by the source app's DPI shifts the marker.
        NativeDesktop.SetWindowPos(handle, new IntPtr(-1), (int)targetPixels.X, (int)targetPixels.Y, 0, 0, 0x0011);
        var dpi = NativeDesktop.GetDpiForWindow(handle);
        var scale = (dpi == 0 ? 96 : dpi) / 96d;
        // A circle that passes just outside the target's corners, plus the 4-unit margin around the stroke.
        var outer = TargetGeometry.OverlayBounds(TargetSnap.Circle(targetPixels, 5 * scale), scale, 4);
        Width = outer.Width / scale;
        Height = outer.Height / scale;
        TargetFrame.Stroke = new SolidColorBrush(verified ? Color.FromRgb(55, 141, 116) : Color.FromRgb(193, 142, 56));
        TargetFrame.StrokeDashArray = verified ? null : new DoubleCollection { 3, 3 };
        if (!IsVisible) Show();
        NativeDesktop.SetWindowPos(handle, new IntPtr(-1), (int)Math.Round(outer.X), (int)Math.Round(outer.Y),
            (int)Math.Round(outer.Width), (int)Math.Round(outer.Height), 0x0010);
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
}

