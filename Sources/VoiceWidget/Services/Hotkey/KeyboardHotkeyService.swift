import Foundation
@preconcurrency import ApplicationServices
import KeyboardShortcuts

@MainActor
public final class KeyboardHotkeyService: GlobalHotkeyService {
    private var toggleHandler: (() -> Void)?
    private var exclusiveKeyCode: Int?
    private var exclusiveEnabled = false
    private var exclusiveBlocksSystemDelivery = true
    nonisolated(unsafe) private var tapExclusiveKeyCode: Int?
    nonisolated(unsafe) private var tapBlocksSystemDelivery = true
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    public init() {}

    public func registerDefaultIfNeeded() {
        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            applyPreset(.optionSpace)
        }
    }

    public func applyPreset(_ preset: HotkeyPreset) {
        guard let shortcut = shortcut(for: preset) else {
            return
        }

        KeyboardShortcuts.setShortcut(shortcut, for: .toggleRecording)
    }

    @discardableResult
    public func configureExclusiveSingleKey(
        keyCode: Int?,
        isEnabled: Bool,
        blocksSystemDelivery: Bool
    ) -> Bool {
        exclusiveKeyCode = keyCode
        exclusiveEnabled = isEnabled && keyCode != nil
        exclusiveBlocksSystemDelivery = blocksSystemDelivery
        tapExclusiveKeyCode = exclusiveEnabled ? keyCode : nil
        tapBlocksSystemDelivery = blocksSystemDelivery

        guard exclusiveEnabled else {
            disableEventTap()
            installKeyboardShortcutHandlerIfNeeded()
            return true
        }

        KeyboardShortcuts.removeHandler(for: .toggleRecording)
        return enableEventTap()
    }

    public func onToggleRecording(_ handler: @escaping () -> Void) {
        toggleHandler = handler
        if exclusiveEnabled {
            _ = enableEventTap()
            return
        }
        installKeyboardShortcutHandlerIfNeeded()
    }

    private func installKeyboardShortcutHandlerIfNeeded() {
        KeyboardShortcuts.removeHandler(for: .toggleRecording)
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.toggleHandler?()
        }
    }

    private func enableEventTap() -> Bool {
        guard eventTap == nil else {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return true
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passRetained(event)
            }

            let service = Unmanaged<KeyboardHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            _ = CGRequestListenEventAccess()
            guard let retryTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                return false
            }

            let retrySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, retryTap, 0)
            guard let retrySource else {
                CFMachPortInvalidate(retryTap)
                return false
            }
            eventTap = retryTap
            eventTapSource = retrySource
            CFRunLoopAddSource(CFRunLoopGetMain(), retrySource, .commonModes)
            CGEvent.tapEnable(tap: retryTap, enable: true)
            return true
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func disableEventTap() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        eventTapSource = nil
    }

    nonisolated private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let expectedKeyCode = tapExclusiveKeyCode, keyCode == expectedKeyCode else {
            return Unmanaged.passRetained(event)
        }

        // Ignore combinations with modifiers; exclusive mode is only for plain single key presses.
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        if !event.flags.intersection(modifierMask).isEmpty {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
            if !isAutorepeat {
                Task { @MainActor [weak self] in
                    self?.toggleHandler?()
                }
            }
        }

        return tapBlocksSystemDelivery ? nil : Unmanaged.passRetained(event)
    }

    private func shortcut(for preset: HotkeyPreset) -> KeyboardShortcuts.Shortcut? {
        switch preset {
        case .optionSpace:
            .init(.space, modifiers: [.option])
        case .controlSpace:
            .init(.space, modifiers: [.control])
        case .commandShiftSpace:
            .init(.space, modifiers: [.command, .shift])
        case .optionReturn:
            .init(.return, modifiers: [.option])
        }
    }
}
