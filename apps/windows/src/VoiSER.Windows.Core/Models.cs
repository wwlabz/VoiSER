namespace VoiSER.Windows.Core;

public sealed record TextDeliveryOutcome(
    TextDeliveryKind Kind,
    TextOutputFallbackReason? FallbackReason = null
);

public sealed record TranscriptionResult(
    string Text,
    string? DetectedLanguage,
    int DurationMs
);

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Win = 8,
}

public sealed record HotkeyCombo(int KeyCode, HotkeyModifiers Modifiers);

public sealed class AppSettings
{
    public bool LaunchAtStartup { get; set; } = true;
    public TextOutputMode TextOutputMode { get; set; } = TextOutputMode.Clipboard;
    public HotkeyCombo ComboHotkey { get; set; } = new(0x20, HotkeyModifiers.Alt); // Alt+Space
    public bool ExclusiveSingleKeyEnabled { get; set; }
    public int ExclusiveSingleKeyCode { get; set; } = 0x20;
    public bool ExclusiveSingleKeyBlocksSystemDelivery { get; set; } = true;
    public string ModelVariant { get; set; } = "small";
}
