import AVFoundation
@preconcurrency import ApplicationServices
import AppKit
import Darwin
import Foundation
import ServiceManagement

public enum TextOutputError: LocalizedError {
    case accessibilityPermissionRequired
    case noFocusedInputField
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Строгий режим вставки: нужен доступ в System Settings -> Privacy & Security -> Accessibility. Для обычной работы выберите режим 'Вставлять в активное поле'."
        case .noFocusedInputField:
            "Не найдено активное поле ввода. Поставьте курсор в текст и повторите."
        case .eventCreationFailed:
            "Не удалось сгенерировать событие вставки."
        }
    }
}

public struct SystemTextOutputService: TextOutputService {
    private static let logQueue = DispatchQueue(label: "VoiSER.TextOutputLog")
    private static let accessibilityPromptStateQueue = DispatchQueue(label: "VoiSER.AccessibilityPromptState")
    nonisolated(unsafe) private static var didPromptForAccessibilityInCurrentLaunch = false

    public init() {}

    public func deliver(
        text: String,
        mode: TextOutputMode,
        preferredTargetBundleIdentifier: String?
    ) throws -> TextDeliveryOutcome {
        log("deliver mode=\(mode.rawValue) preferredTarget=\(preferredTargetBundleIdentifier ?? "nil") frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil") textLength=\(text.count)")
        switch mode {
        case .clipboard:
            copyToPasteboard(text)
            let outcome = TextDeliveryOutcome.copiedToClipboard(reason: .explicitClipboardMode)
            log("outcome=\(String(describing: outcome))")
            return outcome
        case .pasteAtCursor:
            // Use the same insertion path as strict mode because it is more reliable in practice.
            // Difference: this mode gracefully falls back to clipboard on any insertion failure.
            let outcome = pasteUsingStrictPathWithClipboardFallback(
                text: text,
                preferredTargetBundleIdentifier: preferredTargetBundleIdentifier
            )
            log("outcome=\(String(describing: outcome))")
            return outcome
        case .pasteStrict:
            let outcome = try pasteAtCursor(
                text,
                strict: true,
                checkAccessibilityTrust: true,
                preferredTargetBundleIdentifier: preferredTargetBundleIdentifier
            )
            log("outcome=\(String(describing: outcome))")
            return outcome
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteUsingStrictPathWithClipboardFallback(
        text: String,
        preferredTargetBundleIdentifier: String?
    ) -> TextDeliveryOutcome {
        do {
            return try pasteAtCursor(
                text,
                strict: true,
                checkAccessibilityTrust: true,
                preferredTargetBundleIdentifier: preferredTargetBundleIdentifier
            )
        } catch let error as TextOutputError {
            copyToPasteboard(text)
            switch error {
            case .accessibilityPermissionRequired:
                return .copiedToClipboard(reason: .accessibilityUnavailable)
            case .noFocusedInputField:
                return .copiedToClipboard(reason: .noFocusedInputField)
            case .eventCreationFailed:
                return .copiedToClipboard(reason: .pasteEventFailed)
            }
        } catch {
            copyToPasteboard(text)
            return .copiedToClipboard(reason: .pasteEventFailed)
        }
    }

    private func pasteAtCursor(
        _ text: String,
        strict: Bool,
        checkAccessibilityTrust: Bool,
        preferredTargetBundleIdentifier: String?
    ) throws -> TextDeliveryOutcome {
        var accessibilityTrusted = ensureAccessibilityPermission(promptIfNeeded: false)
        if !strict && !accessibilityTrusted {
            // In non-strict mode we still allow clipboard fallback, but prompt once so users
            // can enable real insertion if they selected paste-at-cursor mode.
            accessibilityTrusted = ensureAccessibilityPermission(promptIfNeeded: true)
        }

        if checkAccessibilityTrust && !ensureAccessibilityPermission(promptIfNeeded: true) {
            log("accessibility check failed strict=\(strict)")
            if strict {
                throw TextOutputError.accessibilityPermissionRequired
            }
            copyToPasteboard(text)
            return .copiedToClipboard(reason: .accessibilityUnavailable)
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let resolvedPreferredTargetBundleIdentifier = preferredTargetBundleIdentifier
            ?? inferLikelyTargetBundleIdentifier(excludingBundleIdentifier: ownBundleIdentifier)
        let isOwnAppFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ownBundleIdentifier
        let expectedBundleForFocusCheck = strict ? resolvedPreferredTargetBundleIdentifier : nil
        let targetFrontmostReady: Bool
        if strict || isOwnAppFrontmost {
            targetFrontmostReady = focusPreferredTargetAppIfPossible(bundleIdentifier: resolvedPreferredTargetBundleIdentifier)
        } else {
            targetFrontmostReady = true
        }
        log("frontmost guard strict=\(strict) ownFrontmost=\(isOwnAppFrontmost) targetFrontmostReady=\(targetFrontmostReady) preferredTarget=\(resolvedPreferredTargetBundleIdentifier ?? "nil") frontmostNow=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ownBundleIdentifier {
            log("frontmost remains own app, fallback strict=\(strict)")
            if strict {
                throw TextOutputError.noFocusedInputField
            }
            copyToPasteboard(text)
            return .copiedToClipboard(reason: .noFocusedInputField)
        }

        let focusedElementReady = waitForFocusedElement(
            timeoutMs: 500,
            stepMs: 50,
            expectedBundleIdentifier: expectedBundleForFocusCheck
        )
        log("focus probe strict=\(strict) focusedElementReady=\(focusedElementReady)")

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        copyToPasteboard(text)

        if !strict {
            if accessibilityTrusted {
                let menuTarget = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? resolvedPreferredTargetBundleIdentifier
                if performPasteViaAccessibilityMenu(bundleIdentifier: menuTarget) {
                    log("AX menu paste succeeded")
                    restoreClipboardIfNeeded(
                        previousString: previousString,
                        transientText: text
                    )
                    return .insertedIntoActiveField
                }
                log("AX menu paste failed")

                if focusedElementReady {
                    do {
                        try typeText(text)
                        log("typed unicode primary dispatched")
                        restoreClipboardIfNeeded(
                            previousString: previousString,
                            transientText: text
                        )
                        return .pasteCommandDispatched
                    } catch {
                        log("typed unicode primary failed error=\(error.localizedDescription)")
                    }
                }
            } else {
                log("non-strict: accessibility is not trusted")
            }

            do {
                try sendCommandVUsingSystemEvents()
                log("system events Cmd+V dispatched")
                restoreClipboardIfNeeded(
                    previousString: previousString,
                    transientText: text
                )
                return .pasteCommandDispatched
            } catch {
                log("system events Cmd+V fallback failed error=\(error.localizedDescription)")
            }

            if accessibilityTrusted {
                do {
                    try typeText(text)
                    log("typed unicode fallback dispatched")
                    restoreClipboardIfNeeded(
                        previousString: previousString,
                        transientText: text
                    )
                    return .pasteCommandDispatched
                } catch {
                    log("typed unicode fallback failed error=\(error.localizedDescription)")
                }
            }

            copyToPasteboard(text)
            return .copiedToClipboard(
                reason: accessibilityTrusted ? .pasteEventFailed : .accessibilityUnavailable
            )
        }

        if strict && !(focusedElementReady || targetFrontmostReady) {
            throw TextOutputError.noFocusedInputField
        }

        do {
            try sendCommandV()
            log("sendCommandV succeeded")
        } catch {
            log("sendCommandV failed error=\(error.localizedDescription)")
            if strict {
                throw error
            }
            if performPasteViaAccessibilityMenu(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? resolvedPreferredTargetBundleIdentifier
            ) {
                log("AX menu paste after CGEvent failure succeeded")
                restoreClipboardIfNeeded(
                    previousString: previousString,
                    transientText: text
                )
                return .insertedIntoActiveField
            }
            do {
                try sendCommandVUsingSystemEvents()
                log("system events Cmd+V after CGEvent failure succeeded")
                restoreClipboardIfNeeded(
                    previousString: previousString,
                    transientText: text
                )
                return .insertedIntoActiveField
            } catch {
                log("system events Cmd+V after CGEvent failure failed error=\(error.localizedDescription)")
            }
            do {
                try typeText(text)
                log("typed unicode after Cmd+V failure succeeded")
                restoreClipboardIfNeeded(
                    previousString: previousString,
                    transientText: text
                )
                return .insertedIntoActiveField
            } catch {
                log("typed unicode after Cmd+V failure failed error=\(error.localizedDescription)")
                copyToPasteboard(text)
                return .copiedToClipboard(reason: .pasteEventFailed)
            }
        }

        restoreClipboardIfNeeded(
            previousString: previousString,
            transientText: text
        )

        return .insertedIntoActiveField
    }

    private func inferLikelyTargetBundleIdentifier(excludingBundleIdentifier: String?) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            else {
                continue
            }

            if let app = NSRunningApplication(processIdentifier: ownerPID),
               let bundleIdentifier = app.bundleIdentifier,
               bundleIdentifier != excludingBundleIdentifier {
                return bundleIdentifier
            }
        }

        return nil
    }

    private func sendCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            throw TextOutputError.eventCreationFailed
        }

        commandDown.flags = []
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.post(tap: .cgAnnotatedSessionEventTap)
        vDown.post(tap: .cgAnnotatedSessionEventTap)
        vUp.post(tap: .cgAnnotatedSessionEventTap)
        commandUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func sendCommandVUsingSystemEvents() throws {
        let script = """
        tell application "System Events"
            key code 9 using command down
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)

        if let error {
            throw NSError(domain: "VoiSER.SystemEvents", code: 1, userInfo: error as? [String: Any])
        }
    }

    private func typeText(_ text: String) throws {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty,
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw TextOutputError.eventCreationFailed
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func restoreClipboardIfNeeded(
        previousString: String?,
        transientText: String
    ) {
        guard let previousString else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let pasteboard = NSPasteboard.general
            let current = pasteboard.string(forType: .string)
            if current == transientText {
                pasteboard.clearContents()
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    private func performPasteViaAccessibilityMenu(bundleIdentifier: String?) -> Bool {
        guard
            let bundleIdentifier,
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated })
        else {
            log("ax-menu: missing target app bundle=\(bundleIdentifier ?? "nil")")
            return false
        }

        for attempt in 1...3 {
            _ = app.activate(options: [.activateAllWindows])
            usleep(useconds_t(120_000 * attempt))

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let menuBarRef = copyAttributeValue(element: appElement, attribute: kAXMenuBarAttribute as CFString) else {
                log("ax-menu: attempt=\(attempt) no menu bar")
                continue
            }
            guard CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
                log("ax-menu: attempt=\(attempt) menu bar type mismatch")
                continue
            }

            let menuBar = unsafeDowncast(menuBarRef, to: AXUIElement.self)
            guard let menuBarItems = copyChildren(of: menuBar) else {
                log("ax-menu: attempt=\(attempt) menu bar has no children")
                continue
            }

            let editTitles = ["Edit", "Правка", "Редактировать"]
            guard let editItem = menuBarItems.first(where: { element in
                let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString) ?? ""
                return editTitles.contains(title)
            }) else {
                let titles = menuBarItems.compactMap { copyStringAttribute(element: $0, attribute: kAXTitleAttribute as CFString) }
                log("ax-menu: attempt=\(attempt) no edit item in \(titles)")
                continue
            }

            guard AXUIElementPerformAction(editItem, kAXPressAction as CFString) == .success else {
                log("ax-menu: attempt=\(attempt) failed to open Edit menu")
                continue
            }

            usleep(useconds_t(120_000 * attempt))

            guard let popupMenu = copyChildren(of: editItem)?.first(where: { element in
                copyStringAttribute(element: element, attribute: kAXRoleAttribute as CFString) == "AXMenu"
            }) else {
                log("ax-menu: attempt=\(attempt) no popup AXMenu")
                continue
            }

            guard let menuItems = copyChildren(of: popupMenu) else {
                log("ax-menu: attempt=\(attempt) popup has no items")
                continue
            }

            let pasteTitles = ["Paste", "Вставить"]
            guard let pasteItem = menuItems.first(where: { element in
                let title = copyStringAttribute(element: element, attribute: kAXTitleAttribute as CFString) ?? ""
                return pasteTitles.contains(title)
            }) else {
                let titles = menuItems.compactMap { copyStringAttribute(element: $0, attribute: kAXTitleAttribute as CFString) }
                log("ax-menu: attempt=\(attempt) no Paste item in \(titles.prefix(12))")
                continue
            }

            let enabled = copyBoolAttribute(element: pasteItem, attribute: kAXEnabledAttribute as CFString) ?? true
            if !enabled {
                log("ax-menu: attempt=\(attempt) Paste is disabled")
                continue
            }

            let pressResult = AXUIElementPerformAction(pasteItem, kAXPressAction as CFString)
            if pressResult == .success {
                usleep(120_000)
                return true
            }

            log("ax-menu: attempt=\(attempt) paste press failed status=\(pressResult.rawValue)")
        }

        return false
    }

    private func copyAttributeValue(element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        return status == .success ? value : nil
    }

    private func copyChildren(of element: AXUIElement) -> [AXUIElement]? {
        copyAttributeValue(element: element, attribute: kAXChildrenAttribute as CFString) as? [AXUIElement]
    }

    private func copyStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        copyAttributeValue(element: element, attribute: attribute) as? String
    }

    private func copyBoolAttribute(element: AXUIElement, attribute: CFString) -> Bool? {
        (copyAttributeValue(element: element, attribute: attribute) as? NSNumber)?.boolValue
    }

    @discardableResult
    private func focusPreferredTargetAppIfPossible(bundleIdentifier: String?) -> Bool {
        guard
            let bundleIdentifier,
            let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated })
        else {
            return false
        }

        _ = target.activate(options: [.activateAllWindows])
        return waitForFrontmostApplication(
            bundleIdentifier: bundleIdentifier,
            timeoutMs: 900,
            stepMs: 50
        )
    }

    private func waitForFocusedElement(
        timeoutMs: Int,
        stepMs: Int,
        expectedBundleIdentifier: String?
    ) -> Bool {
        let attempts = max(1, timeoutMs / max(1, stepMs))

        for _ in 0..<attempts {
            if hasFocusedElement(inExpectedApp: expectedBundleIdentifier) {
                return true
            }
            usleep(useconds_t(stepMs * 1_000))
        }
        return false
    }

    private func waitForFrontmostApplication(
        bundleIdentifier: String,
        timeoutMs: Int,
        stepMs: Int
    ) -> Bool {
        let attempts = max(1, timeoutMs / max(1, stepMs))
        for _ in 0..<attempts {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
                return true
            }
            usleep(useconds_t(stepMs * 1_000))
        }
        return false
    }

    private func ensureAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        guard promptIfNeeded else {
            return false
        }

        let shouldPrompt = Self.accessibilityPromptStateQueue.sync { () -> Bool in
            if Self.didPromptForAccessibilityInCurrentLaunch {
                return false
            }
            Self.didPromptForAccessibilityInCurrentLaunch = true
            return true
        }
        guard shouldPrompt else {
            return false
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func hasFocusedElement(inExpectedApp expectedBundleIdentifier: String?) -> Bool {
        if let expectedBundleIdentifier {
            let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontmostBundleIdentifier != expectedBundleIdentifier {
                return false
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        return status == .success && focusedElement != nil
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        Self.logQueue.async {
            let fm = FileManager.default
            let directory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Logs/VoiSER", isDirectory: true)
            let fileURL = directory.appendingPathComponent("text-output.log")

            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: fileURL.path) {
                    try line.data(using: .utf8)?.write(to: fileURL)
                    return
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                // Best effort diagnostics only.
            }
        }
    }
}

@MainActor
public final class MicrophonePermissionManager: MicrophonePermissionProviding {
    private enum Keys {
        static let didRequestMicAccess = "didRequestMicAccess"
        static let cachedMicAccessGranted = "cachedMicAccessGranted"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var status: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            cachePermission(granted: true)
            return .granted
        case .denied:
            cachePermission(granted: false)
            return .denied
        case .undetermined:
            guard defaults.bool(forKey: Keys.didRequestMicAccess) else {
                return .notDetermined
            }
            return defaults.bool(forKey: Keys.cachedMicAccessGranted) ? .granted : .denied
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            cachePermission(granted: true)
            return true
        case .denied:
            cachePermission(granted: false)
            return false
        case .undetermined:
            if defaults.bool(forKey: Keys.didRequestMicAccess) {
                return defaults.bool(forKey: Keys.cachedMicAccessGranted)
            }

            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        continuation.resume(returning: granted)
                    }
                }
            }

            cachePermission(granted: granted)
            return granted
        @unknown default:
            cachePermission(granted: false)
            return false
        }
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func cachePermission(granted: Bool) {
        defaults.set(true, forKey: Keys.didRequestMicAccess)
        defaults.set(granted, forKey: Keys.cachedMicAccessGranted)
    }
}

@MainActor
public struct LaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
public struct SystemAlertPresenter: AlertPresenting {
    public init() {}

    public func showMicrophoneAccessAlert(openSettings: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Разрешите доступ к микрофону"
        alert.informativeText = "Без доступа к микрофону запись голоса недоступна."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Отмена")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSettings()
        }
    }
}
