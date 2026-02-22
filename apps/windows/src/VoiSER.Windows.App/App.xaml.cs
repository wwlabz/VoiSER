using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace VoiSER.Windows.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        StartupDiagnostics.Write("App constructor initialized.");
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnCurrentDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            StartupDiagnostics.Write("OnLaunched called.");
            _window = new MainWindow();
            _window.Activate();
            StartupDiagnostics.Write("MainWindow activated.");
        }
        catch (Exception ex)
        {
            StartupDiagnostics.WriteException("Fatal error during OnLaunched", ex);
            ShowFatalError(
                "VoiSER crashed during startup.\n\n" +
                $"Crash log: {StartupDiagnostics.LogFilePath}\n\n" +
                ex.Message
            );
            throw;
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        StartupDiagnostics.WriteException("Unhandled XAML exception", e.Exception);
        e.Handled = true;
        ShowFatalError(
            "VoiSER encountered an unhandled UI exception.\n\n" +
            $"Crash log: {StartupDiagnostics.LogFilePath}\n\n" +
            e.Exception.Message
        );
        Current?.Exit();
    }

    private void OnCurrentDomainUnhandledException(object? sender, UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            StartupDiagnostics.WriteException("Unhandled AppDomain exception", ex);
        }
        else
        {
            StartupDiagnostics.Write($"Unhandled AppDomain exception object: {e.ExceptionObject}");
        }
    }

    private void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        StartupDiagnostics.WriteException("Unobserved task exception", e.Exception);
        e.SetObserved();
    }

    private static void ShowFatalError(string message)
    {
        const uint mbIconError = 0x00000010;
        _ = MessageBox(IntPtr.Zero, message, "VoiSER", mbIconError);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int MessageBox(IntPtr hWnd, string lpText, string lpCaption, uint uType);
}

internal static class StartupDiagnostics
{
    private static readonly object Sync = new();
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "VoiSER",
        "logs",
        "startup.log"
    );

    public static string LogFilePath => LogPath;

    public static void Write(string message)
    {
        try
        {
            var directory = Path.GetDirectoryName(LogPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            lock (Sync)
            {
                File.AppendAllText(
                    LogPath,
                    $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}"
                );
            }
        }
        catch
        {
            // Startup diagnostics should never crash the app.
        }
    }

    public static void WriteException(string context, Exception ex)
    {
        Write($"{context}: {ex}");
    }
}
