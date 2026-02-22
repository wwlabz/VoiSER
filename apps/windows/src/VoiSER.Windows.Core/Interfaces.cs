namespace VoiSER.Windows.Core;

public interface IHotkeyService
{
    event Action? Triggered;
    bool ConfigureCombo(HotkeyCombo combo);
    bool ConfigureSingleKey(int keyCode, bool enabled, bool blockSystemDelivery);
}

public interface IAudioCaptureService
{
    Task StartAsync(CancellationToken cancellationToken = default);
    Task<string> StopAsync(CancellationToken cancellationToken = default);
}

public interface ITranscriptionService
{
    Task<TranscriptionResult> TranscribeAsync(string audioFilePath, CancellationToken cancellationToken = default);
}

public interface ITextOutputService
{
    Task<TextDeliveryOutcome> DeliverAsync(string text, TextOutputMode mode, CancellationToken cancellationToken = default);
}

public interface ISettingsStore
{
    Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default);
}

public interface IModelManager
{
    Task EnsureModelReadyAsync(string variant, IProgress<(double Progress, string Message)>? progress = null, CancellationToken cancellationToken = default);
    string ModelDirectory(string variant);
}
