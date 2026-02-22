using System.Runtime.InteropServices;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public interface IClipboardClient
{
    Task SetTextAsync(string text, CancellationToken cancellationToken = default);
}

public sealed class WindowsFormsClipboardClient : IClipboardClient
{
    public Task SetTextAsync(string text, CancellationToken cancellationToken = default)
    {
        System.Windows.Forms.Clipboard.SetText(text);
        return Task.CompletedTask;
    }
}

public sealed class TextOutputService : ITextOutputService
{
    private readonly IClipboardClient _clipboard;

    public TextOutputService(IClipboardClient? clipboard = null)
    {
        _clipboard = clipboard ?? new WindowsFormsClipboardClient();
    }

    public async Task<TextDeliveryOutcome> DeliverAsync(string text, TextOutputMode mode, CancellationToken cancellationToken = default)
    {
        await _clipboard.SetTextAsync(text, cancellationToken);

        if (mode == TextOutputMode.Clipboard)
        {
            return new TextDeliveryOutcome(TextDeliveryKind.CopiedToClipboard, TextOutputFallbackReason.ExplicitClipboardMode);
        }

        var pasted = TrySendPasteShortcut();
        if (pasted)
        {
            return mode == TextOutputMode.PasteStrict
                ? new TextDeliveryOutcome(TextDeliveryKind.InsertedIntoActiveField)
                : new TextDeliveryOutcome(TextDeliveryKind.PasteCommandDispatched);
        }

        if (mode == TextOutputMode.PasteStrict)
        {
            throw new InvalidOperationException("Strict paste failed: unable to dispatch Ctrl+V to focused target.");
        }

        return new TextDeliveryOutcome(TextDeliveryKind.CopiedToClipboard, TextOutputFallbackReason.PasteEventFailed);
    }

    private static bool TrySendPasteShortcut()
    {
        try
        {
            INPUT[] inputs =
            [
                INPUT.Keyboard((ushort)VirtualKey.CONTROL, keyUp: false),
                INPUT.Keyboard((ushort)VirtualKey.V, keyUp: false),
                INPUT.Keyboard((ushort)VirtualKey.V, keyUp: true),
                INPUT.Keyboard((ushort)VirtualKey.CONTROL, keyUp: true),
            ];

            var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
            return sent == inputs.Length;
        }
        catch
        {
            return false;
        }
    }

    private enum VirtualKey : ushort
    {
        CONTROL = 0x11,
        V = 0x56,
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint Type;
        public InputUnion Data;

        public static INPUT Keyboard(ushort vk, bool keyUp)
        {
            return new INPUT
            {
                Type = 1,
                Data = new InputUnion
                {
                    Keyboard = new KEYBDINPUT
                    {
                        Vk = vk,
                        Scan = 0,
                        Flags = keyUp ? 0x0002u : 0,
                        Time = 0,
                        ExtraInfo = IntPtr.Zero,
                    }
                }
            };
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort Vk;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
