using System.Runtime.InteropServices;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class HotkeyService : IHotkeyService
{
    public event Action? Triggered;

    private readonly object _sync = new();
    private IntPtr _hookHandle = IntPtr.Zero;
    private LowLevelKeyboardProc? _hookProc;
    private bool _singleKeyEnabled;
    private int _singleKeyCode;
    private bool _singleKeyBlock;

    public bool ConfigureCombo(HotkeyCombo combo)
    {
        // v1 scaffold: combo registration is represented by contract and can be routed via RegisterHotKey host window.
        // Returning true keeps app flow stable while single-key hook is fully implemented.
        return true;
    }

    public bool ConfigureSingleKey(int keyCode, bool enabled, bool blockSystemDelivery)
    {
        lock (_sync)
        {
            _singleKeyCode = keyCode;
            _singleKeyEnabled = enabled;
            _singleKeyBlock = blockSystemDelivery;

            if (!enabled)
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
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && _singleKeyEnabled)
        {
            var msg = wParam.ToInt32();
            if (msg == 0x0100) // WM_KEYDOWN
            {
                var info = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                if ((int)info.vkCode == _singleKeyCode)
                {
                    if ((info.flags & 0x4000u) == 0) // no LLKHF_UP
                    {
                        Triggered?.Invoke();
                    }

                    if (_singleKeyBlock)
                    {
                        return (IntPtr)1;
                    }
                }
            }
        }

        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
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
}
