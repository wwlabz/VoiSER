namespace VoiSER.Windows.Core;

public enum CaptureState
{
    Idle,
    Recording,
    Transcribing,
    Failed,
}

public enum TextOutputMode
{
    Clipboard,
    PasteAtCursor,
    PasteStrict,
}

public enum TextOutputFallbackReason
{
    ExplicitClipboardMode,
    AccessibilityUnavailable,
    NoFocusedInputField,
    PasteEventFailed,
}

public enum TextDeliveryKind
{
    CopiedToClipboard,
    InsertedIntoActiveField,
    PasteCommandDispatched,
}
