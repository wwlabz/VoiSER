using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiSER.Windows.Core;
using VoiSER.Windows.Infrastructure;

namespace VoiSER.Windows.App;

public sealed partial class MainWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private readonly IHotkeyService _hotkeyService;
    private readonly IAudioCaptureService _audioCaptureService;
    private readonly ITranscriptionService _transcriptionService;
    private readonly ITextOutputService _textOutputService;

    private AppSettings _settings = new();
    private string? _lastAudioFile;
    private bool _isRecording;

    public MainWindow()
    {
        InitializeComponent();

        _settingsStore = new JsonSettingsStore();
        var modelManager = new ModelManager();
        _hotkeyService = new HotkeyService();
        _audioCaptureService = new NAudioCaptureService();
        _transcriptionService = new WhisperTranscriptionService(modelManager);
        _textOutputService = new TextOutputService();

        _hotkeyService.Triggered += () => DispatcherQueue.TryEnqueue(() => _ = ToggleCaptureAsync());

        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        _settings = await _settingsStore.LoadAsync();

        OutputModeCombo.SelectedIndex = _settings.TextOutputMode switch
        {
            TextOutputMode.Clipboard => 0,
            TextOutputMode.PasteAtCursor => 1,
            TextOutputMode.PasteStrict => 2,
            _ => 0,
        };

        SingleKeyEnabled.IsChecked = _settings.ExclusiveSingleKeyEnabled;
        SingleKeyBlock.IsChecked = _settings.ExclusiveSingleKeyBlocksSystemDelivery;
        SingleKeyCode.Value = _settings.ExclusiveSingleKeyCode;

        ApplyHotkeyConfig();
        AppendLog("Initialized settings and hotkeys.");
    }

    private async Task ToggleCaptureAsync()
    {
        if (!_isRecording)
        {
            await _audioCaptureService.StartAsync();
            _isRecording = true;
            StateLabel.Text = "State: Recording";
            AppendLog("Recording started.");
            return;
        }

        _lastAudioFile = await _audioCaptureService.StopAsync();
        _isRecording = false;
        StateLabel.Text = "State: Transcribing";
        AppendLog($"Recording stopped: {_lastAudioFile}");

        var result = await _transcriptionService.TranscribeAsync(_lastAudioFile);
        var output = await _textOutputService.DeliverAsync(result.Text, _settings.TextOutputMode);
        StateLabel.Text = "State: Idle";
        AppendLog($"Transcription text: {result.Text}");
        AppendLog($"Output outcome: {output.Kind} {output.FallbackReason}");
    }

    private async void OnToggleRecordingClick(object sender, RoutedEventArgs e)
    {
        await ToggleCaptureAsync();
    }

    private async void OnOutputModeChanged(object sender, SelectionChangedEventArgs e)
    {
        _settings.TextOutputMode = OutputModeCombo.SelectedIndex switch
        {
            1 => TextOutputMode.PasteAtCursor,
            2 => TextOutputMode.PasteStrict,
            _ => TextOutputMode.Clipboard,
        };
        await _settingsStore.SaveAsync(_settings);
    }

    private async void OnSingleKeyConfigChanged(object sender, RoutedEventArgs e)
    {
        _settings.ExclusiveSingleKeyEnabled = SingleKeyEnabled.IsChecked == true;
        _settings.ExclusiveSingleKeyBlocksSystemDelivery = SingleKeyBlock.IsChecked == true;
        ApplyHotkeyConfig();
        await _settingsStore.SaveAsync(_settings);
    }

    private async void OnSingleKeyCodeChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _settings.ExclusiveSingleKeyCode = (int)sender.Value;
        ApplyHotkeyConfig();
        await _settingsStore.SaveAsync(_settings);
    }

    private void ApplyHotkeyConfig()
    {
        _hotkeyService.ConfigureCombo(_settings.ComboHotkey);
        var ok = _hotkeyService.ConfigureSingleKey(
            _settings.ExclusiveSingleKeyCode,
            _settings.ExclusiveSingleKeyEnabled,
            _settings.ExclusiveSingleKeyBlocksSystemDelivery
        );

        if (!ok)
        {
            AppendLog("Single-key hook activation failed. Check security restrictions/input permissions.");
        }
    }

    private void AppendLog(string message)
    {
        LogBox.Text = $"{DateTime.Now:HH:mm:ss} {message}\n{LogBox.Text}";
    }
}
