using System.Threading;
using System.Windows;

namespace F2L.Windows;

public partial class App : Application
{
    private Mutex? _singleInstance;
    private EventWaitHandle? _openRequest;
    private RegisteredWaitHandle? _openListener;
    internal bool StartCompanionOnStartup { get; set; } = true;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (!StartCompanionOnStartup) return;
        _singleInstance = new Mutex(true, @"Local\F2L.Companion", out var first);
        _openRequest = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\F2L.Companion.Open");
        if (!first)
        {
            // Pip is already running: opening F2L again brings its conversation up, as reopening the Mac app does.
            _openRequest.Set();
            Shutdown();
            return;
        }
        var window = new MainWindow();
        window.ShowWithIntro();
        _openListener = ThreadPool.RegisterWaitForSingleObject(_openRequest,
            (_, _) => Dispatcher.InvokeAsync(window.OpenConversation), null, Timeout.Infinite, false);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _openListener?.Unregister(null);
        _openRequest?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
