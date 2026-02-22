using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
    private readonly IModelManager _modelManager;

    private AppSettings _settings = new();
    private bool _isRecording;
    private bool _isCapturingSingleKey;
    private bool _isUiReady;

    public MainWindow()
    {
        try
        {
            _settingsStore = new JsonSettingsStore();
            _modelManager = new ModelManager();
            _hotkeyService = new HotkeyService();
            _audioCaptureService = new NAudioCaptureService();
            _transcriptionService = new WhisperTranscriptionService(_modelManager);
            _textOutputService = new TextOutputService();

            InitializeComponent();

            _hotkeyService.Triggered += () => DispatcherQueue.TryEnqueue(() => _ = ToggleCaptureAsync());

            _ = InitializeAsync();
        }
        catch (Exception ex)
        {
            StartupDiagnostics.WriteException("MainWindow constructor failed", ex);
            throw;
        }
    }

    private async Task InitializeAsync()
    {
        try
        {
            _isUiReady = false;
            _settings = await _settingsStore.LoadAsync();

            OutputModes.SelectedIndex = _settings.TextOutputMode switch
            {
                TextOutputMode.Clipboard => 0,
                TextOutputMode.PasteAtCursor => 1,
                TextOutputMode.PasteStrict => 2,
                _ => 0,
            };

            var variants = new[] { "tiny", "base", "small", "medium" };
            ModelVariantCombo.SelectedIndex = Array.IndexOf(variants, _settings.ModelVariant);
            if (ModelVariantCombo.SelectedIndex < 0) ModelVariantCombo.SelectedIndex = 2;

            LaunchAtStartup.IsChecked = _settings.LaunchAtStartup;
            WidgetEnabled.IsChecked = true;

            SingleKeyEnabled.IsChecked = _settings.ExclusiveSingleKeyEnabled;
            SingleKeyBlock.IsChecked = _settings.ExclusiveSingleKeyBlocksSystemDelivery;
            SingleKeyLabel.Text = FormatScanCode(_settings.ExclusiveSingleKeyCode);

            ComboKeyCode.Value = _settings.ComboHotkey.KeyCode;
            ComboAlt.IsChecked = _settings.ComboHotkey.Modifiers.HasFlag(HotkeyModifiers.Alt);
            ComboCtrl.IsChecked = _settings.ComboHotkey.Modifiers.HasFlag(HotkeyModifiers.Control);
            ComboShift.IsChecked = _settings.ComboHotkey.Modifiers.HasFlag(HotkeyModifiers.Shift);
            ComboWin.IsChecked = _settings.ComboHotkey.Modifiers.HasFlag(HotkeyModifiers.Win);

            ApplyHotkeyConfig();
            _isUiReady = true;
            AppendLog("Инициализация завершена");

            await EnsureModelReadyOnStartupAsync();
        }
        catch (Exception ex)
        {
            StartupDiagnostics.WriteException("MainWindow.InitializeAsync failed", ex);
            AppendLog($"Критическая ошибка инициализации: {ex.Message}");
            StateLabel.Text = "Состояние: Failed";
        }
    }

    private async Task EnsureModelReadyOnStartupAsync()
    {
        var progress = new Progress<(double Progress, string Message)>(p =>
        {
            ModelProgress.Value = p.Progress;
            ModelMessage.Text = p.Message;
        });

        try
        {
            ModelMessage.Text = "Подготовка модели Whisper…";
            await _modelManager.EnsureModelReadyAsync(_settings.ModelVariant, progress);
            ModelMessage.Text = "Модель готова";
            ModelProgress.Value = 1;
        }
        catch (Exception ex)
        {
            ModelMessage.Text = "Ошибка подготовки модели";
            AppendLog($"[model] {ex.Message}");
        }
    }

    private async Task ToggleCaptureAsync()
    {
        if (!_isRecording)
        {
            await _audioCaptureService.StartAsync();
            _isRecording = true;
            StateLabel.Text = "Состояние: Recording";
            AppendLog("Запись начата");
            return;
        }

        var audioFile = await _audioCaptureService.StopAsync();
        _isRecording = false;
        StateLabel.Text = "Состояние: Transcribing";
        AppendLog($"Запись остановлена: {audioFile}");

        try
        {
            var result = await _transcriptionService.TranscribeAsync(audioFile);
            if (string.IsNullOrWhiteSpace(result.Text))
            {
                AppendLog("Тишина или слишком короткая запись");
                StateLabel.Text = "Состояние: Idle";
                return;
            }

            var output = await _textOutputService.DeliverAsync(result.Text, _settings.TextOutputMode);
            AppendLog($"Текст: {result.Text}");
            AppendLog($"Вывод: {output.Kind} {output.FallbackReason}");
        }
        catch (Exception ex)
        {
            AppendLog($"Ошибка: {ex.Message}");
        }
        finally
        {
            StateLabel.Text = "Состояние: Idle";
        }
    }

    private async void OnToggleRecordingClick(object sender, RoutedEventArgs e) => await ToggleCaptureAsync();

    private async void OnOutputModeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        _settings.TextOutputMode = OutputModes.SelectedIndex switch
        {
            1 => TextOutputMode.PasteAtCursor,
            2 => TextOutputMode.PasteStrict,
            _ => TextOutputMode.Clipboard,
        };
        await _settingsStore.SaveAsync(_settings);
    }

    private async void OnModelVariantChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        if (ModelVariantCombo.SelectedItem is ComboBoxItem item && item.Content is string variant)
        {
            _settings.ModelVariant = variant;
            await _settingsStore.SaveAsync(_settings);
            AppendLog($"Модель: {variant}");
        }
    }

    private async void OnPrepareModelClick(object sender, RoutedEventArgs e) => await EnsureModelReadyOnStartupAsync();

    private void OnCaptureKeyClick(object sender, RoutedEventArgs e)
    {
        _isCapturingSingleKey = true;
        CaptureKeyButton.Content = "Нажмите клавишу…";
        AppendLog("Ожидание нажатия клавиши для single-key режима");
    }

    private async void OnWindowKeyDownCapture(object sender, KeyRoutedEventArgs e)
    {
        if (!_isCapturingSingleKey)
        {
            return;
        }

        var scanCode = (int)e.KeyStatus.ScanCode;
        if (scanCode <= 0)
        {
            scanCode = (int)e.Key;
        }

        _settings.ExclusiveSingleKeyCode = scanCode;
        SingleKeyLabel.Text = FormatScanCode(scanCode);
        _isCapturingSingleKey = false;
        CaptureKeyButton.Content = "Назначить клавишу";
        ApplyHotkeyConfig();
        await _settingsStore.SaveAsync(_settings);

        e.Handled = true;
        AppendLog($"Single-key назначен: {FormatScanCode(scanCode)}");
    }

    private async void OnSingleKeyConfigChanged(object sender, RoutedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        _settings.ExclusiveSingleKeyEnabled = SingleKeyEnabled.IsChecked == true;
        _settings.ExclusiveSingleKeyBlocksSystemDelivery = SingleKeyBlock.IsChecked == true;
        ApplyHotkeyConfig();
        await _settingsStore.SaveAsync(_settings);
    }

    private async void OnComboKeyCodeChanged(NumberBox sender, NumberBoxValueChangedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        await SaveComboHotkeyFromControlsAsync();
    }

    private async void OnComboModifiersChanged(object sender, RoutedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        await SaveComboHotkeyFromControlsAsync();
    }

    private async Task SaveComboHotkeyFromControlsAsync()
    {
        var modifiers = HotkeyModifiers.None;
        if (ComboAlt.IsChecked == true) modifiers |= HotkeyModifiers.Alt;
        if (ComboCtrl.IsChecked == true) modifiers |= HotkeyModifiers.Control;
        if (ComboShift.IsChecked == true) modifiers |= HotkeyModifiers.Shift;
        if (ComboWin.IsChecked == true) modifiers |= HotkeyModifiers.Win;

        var keyCodeValue = ComboKeyCode.Value;
        if (double.IsNaN(keyCodeValue) || double.IsInfinity(keyCodeValue))
        {
            AppendLog("Неверное значение VK-кода хоткея");
            return;
        }

        var keyCode = (int)Math.Clamp(keyCodeValue, 1, 255);
        _settings.ComboHotkey = new HotkeyCombo(keyCode, modifiers);
        ApplyHotkeyConfig();
        await _settingsStore.SaveAsync(_settings);
    }

    private async void OnBehaviorChanged(object sender, RoutedEventArgs e)
    {
        if (!_isUiReady)
        {
            return;
        }

        _settings.LaunchAtStartup = LaunchAtStartup.IsChecked == true;
        await _settingsStore.SaveAsync(_settings);
    }

    private void OnCheckPermissionsClick(object sender, RoutedEventArgs e)
    {
        AppendLog("Windows: проверьте доступ к микрофону и ограничения безопасности (Defender/AV) для hooks/injection.");
    }

    private async void OnReinitializeModelClick(object sender, RoutedEventArgs e)
    {
        var path = _modelManager.ModelDirectory(_settings.ModelVariant);
        if (Directory.Exists(path))
        {
            Directory.Delete(path, true);
        }

        AppendLog("Каталог модели удален, запускаю повторную подготовку...");
        await EnsureModelReadyOnStartupAsync();
    }

    private void ApplyHotkeyConfig()
    {
        var comboOk = _hotkeyService.ConfigureCombo(_settings.ComboHotkey);
        var singleKeyOk = _hotkeyService.ConfigureSingleKey(
            _settings.ExclusiveSingleKeyCode,
            _settings.ExclusiveSingleKeyEnabled,
            _settings.ExclusiveSingleKeyBlocksSystemDelivery
        );

        if (!comboOk || !singleKeyOk)
        {
            AppendLog("Не удалось активировать глобальные перехваты клавиш. Проверьте политики безопасности.");
        }
    }

    private static string FormatScanCode(int code) => $"SC-{code}";

    private void AppendLog(string message)
    {
        var sb = new StringBuilder();
        sb.Append(DateTime.Now.ToString("HH:mm:ss"));
        sb.Append(' ');
        sb.Append(message);
        sb.AppendLine();
        sb.Append(LogBox.Text);
        LogBox.Text = sb.ToString();
    }
}
