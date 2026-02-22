using System.Runtime.InteropServices;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class HotkeyService : IHotkeyService
{
    public event Action? Triggered;

    private readonly object _sync = new();
    private IntPtr _hookHandle = IntPtr.Zero;
    private LowLevelKeyboardProc? _hookProc;

    private HotkeyCombo _combo = new(0x20, HotkeyModifiers.Alt);
    private bool _singleKeyEnabled;
    private int _singleKeyCode;
    private bool _singleKeyBlock;

    private readonly HashSet<uint> _pressedKeys = [];

    public bool ConfigureCombo(HotkeyCombo combo)
    {
        lock (_sync)
        {
            _combo = combo;
            return EnsureHook();
        }
    }

    public bool ConfigureSingleKey(int keyCode, bool enabled, bool blockSystemDelivery)
    {
        lock (_sync)
        {
            _singleKeyCode = keyCode;
            _singleKeyEnabled = enabled;
            _singleKeyBlock = blockSystemDelivery;

            if (!enabled && _combo.Modifiers == HotkeyModifiers.None && _combo.KeyCode == 0)
            {
                UninstallHook();
                return true;
            }

            return EnsureHook();
        }
    }

    private bool EnsureHook()
    {
        if (_hookHandle != IntPtr.Zero)
        {
            return true;
        }

        _hookProc = HookCallback;
        _hookHandle = SetWindowsHookEx(13, _hookProc, IntPtr.Zero, 0);
        return _hookHandle != IntPtr.Zero;
    }

    private void UninstallHook()
    {
        if (_hookHandle == IntPtr.Zero)
        {
            return;
        }

        UnhookWindowsHookEx(_hookHandle);
        _hookHandle = IntPtr.Zero;
        _hookProc = null;
        _pressedKeys.Clear();
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
        {
            return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
        }

        var msg = wParam.ToInt32();
        var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);

        if (msg == 0x0100) // WM_KEYDOWN
        {
            var wasPressed = !_pressedKeys.Add(info.vkCode);
            var triggerSingle = _singleKeyEnabled && (int)info.scanCode == _singleKeyCode;
            var triggerCombo = MatchesCombo((int)info.vkCode);

            if (!wasPressed && (triggerSingle || triggerCombo))
            {
                Triggered?.Invoke();
            }

            if (triggerSingle && _singleKeyBlock)
            {
                return (IntPtr)1;
            }
        }
        else if (msg == 0x0101) // WM_KEYUP
        {
            _pressedKeys.Remove(info.vkCode);
        }

        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    private bool MatchesCombo(int keyCode)
    {
        if (_combo.KeyCode != keyCode)
        {
            return false;
        }

        bool alt = IsModifierDown(0x12);
        bool ctrl = IsModifierDown(0x11);
        bool shift = IsModifierDown(0x10);
        bool win = IsModifierDown(0x5B) || IsModifierDown(0x5C);

        if (_combo.Modifiers.HasFlag(HotkeyModifiers.Alt) != alt) return false;
        if (_combo.Modifiers.HasFlag(HotkeyModifiers.Control) != ctrl) return false;
        if (_combo.Modifiers.HasFlag(HotkeyModifiers.Shift) != shift) return false;
        if (_combo.Modifiers.HasFlag(HotkeyModifiers.Win) != win) return false;

        return true;
    }

    private static bool IsModifierDown(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
}
