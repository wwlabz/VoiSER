import AppKit
import Foundation
import SwiftUI

@MainActor
public final class OverlayWindowController: NSObject, OverlayWidgetController, NSWindowDelegate {
    private enum UI {
        static let widgetSize = CGSize(width: 140, height: 150)
    }

    private let settingsStore: AppSettingsStore
    private let viewModel: OverlayWidgetViewModel

    private var window: NSPanel?
    private var toggleHandler: (() -> Void)?
    private var retryModelHandler: (() -> Void)?
    private var openSettingsHandler: (() -> Void)?
    private var resetPositionHandler: (() -> Void)?
    private var modelSelectionHandler: ((WhisperModelOption) -> Void)?
    private var hotkeySelectionHandler: ((HotkeyPreset) -> Void)?
    private var widgetStyleSelectionHandler: ((WidgetStyleOption) -> Void)?
    private var persistWorkItem: DispatchWorkItem?
    private var dragOrigin: CGPoint?
    private var dragVisibleFrame: CGRect?

    public init(settingsStore: AppSettingsStore, viewModel: OverlayWidgetViewModel = .init()) {
        self.settingsStore = settingsStore
        self.viewModel = viewModel
        super.init()
    }

    public func setToggleHandler(_ handler: @escaping () -> Void) {
        toggleHandler = handler
    }

    public func setRetryModelHandler(_ handler: @escaping () -> Void) {
        retryModelHandler = handler
    }

    public func setOpenSettingsHandler(_ handler: @escaping () -> Void) {
        openSettingsHandler = handler
    }

    public func setResetPositionHandler(_ handler: @escaping () -> Void) {
        resetPositionHandler = handler
    }

    public func setModelSelectionHandler(_ handler: @escaping (WhisperModelOption) -> Void) {
        modelSelectionHandler = handler
    }

    public func setHotkeySelectionHandler(_ handler: @escaping (HotkeyPreset) -> Void) {
        hotkeySelectionHandler = handler
    }

    public func setWidgetStyleSelectionHandler(_ handler: @escaping (WidgetStyleOption) -> Void) {
        widgetStyleSelectionHandler = handler
    }

    public func setSelectedModel(_ model: WhisperModelOption) {
        viewModel.selectedModel = model
    }

    public func setSelectedHotkeyPreset(_ preset: HotkeyPreset) {
        viewModel.hotkeyPreset = preset
    }

    public func setSelectedWidgetStyle(_ style: WidgetStyleOption) {
        viewModel.widgetStyle = style
        guard let window else {
            return
        }

        if style == .notchTop {
            let origin = defaultOrigin(for: window.frame.size)
            let clamped = clampedOrigin(for: origin, size: window.frame.size)
            window.setFrameOrigin(clamped)
            settingsStore.widgetOrigin = clamped
        }
    }

    public func setInputLevel(_ level: Float) {
        viewModel.pushInputLevel(level)
    }

    public func show() {
        if window == nil {
            window = makeWindow()
        }

        guard let window else {
            return
        }

        if let savedOrigin = settingsStore.widgetOrigin {
            window.setFrameOrigin(clampedOrigin(for: savedOrigin, size: window.frame.size))
        }

        window.orderFrontRegardless()
    }

    public func setVisible(_ isVisible: Bool) {
        guard let window else {
            return
        }

        if isVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    public func update(state: CaptureState) {
        viewModel.state = state
        if case .failed = state {
            viewModel.canRetryModel = true
            viewModel.resetInputLevels()
        } else {
            viewModel.canRetryModel = false
        }
    }

    public func setMessage(_ message: String?) {
        viewModel.message = message
    }

    public func persistPosition() {
        guard let window else {
            return
        }

        let clamped = clampedOrigin(for: window.frame.origin, size: window.frame.size)
        window.setFrameOrigin(clamped)
        settingsStore.widgetOrigin = clamped
    }

    public func resetPosition() {
        settingsStore.clearWidgetOrigin()
        guard let window else {
            return
        }

        let origin = defaultOrigin(for: window.frame.size)
        window.setFrameOrigin(origin)
    }

    private func makeWindow() -> NSPanel {
        let initialOrigin = settingsStore.widgetOrigin ?? defaultOrigin(for: UI.widgetSize)
        let frame = CGRect(origin: clampedOrigin(for: initialOrigin, size: UI.widgetSize), size: UI.widgetSize)

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.delegate = self

        let rootView = OverlayWidgetView(
            viewModel: viewModel,
            onTap: { [weak self] in
                self?.toggleHandler?()
            },
            onRetry: { [weak self] in
                self?.retryModelHandler?()
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsHandler?()
            },
            onResetPosition: { [weak self] in
                if let handler = self?.resetPositionHandler {
                    handler()
                } else {
                    self?.resetPosition()
                }
            },
            onSelectModel: { [weak self] model in
                self?.modelSelectionHandler?(model)
            },
            onSelectHotkey: { [weak self] preset in
                self?.hotkeySelectionHandler?(preset)
            },
            onSelectStyle: { [weak self] style in
                self?.widgetStyleSelectionHandler?(style)
            },
            onDragBegan: { [weak self] in
                guard let self, let window = self.window else {
                    return
                }
                self.dragOrigin = window.frame.origin
                self.dragVisibleFrame = self.visibleFrame(for: window.frame.origin, itemSize: window.frame.size)
            },
            onDragChanged: { [weak self] translation in
                self?.moveWindow(with: translation)
            },
            onDragEnded: { [weak self] in
                self?.dragVisibleFrame = nil
                self?.persistPosition()
            }
        )

        window.contentView = NSHostingView(rootView: rootView)
        return window
    }

    private func moveWindow(with translation: CGSize) {
        guard let window, let dragOrigin else {
            return
        }

        let translated = CGPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y - translation.height
        )

        let frame = dragVisibleFrame ?? visibleFrame(for: translated, itemSize: window.frame.size)
        let clamped = clampedOrigin(for: translated, size: window.frame.size, in: frame)
        if clamped != window.frame.origin {
            window.setFrameOrigin(clamped)
        }
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let frame = primaryVisibleFrame()
        let x = frame.midX - (size.width / 2)
        let y: CGFloat
        if viewModel.widgetStyle == .notchTop {
            y = frame.maxY - size.height - 10
        } else {
            y = frame.minY + 24
        }
        return CGPoint(x: x, y: y)
    }

    private func clampedOrigin(for origin: CGPoint, size: CGSize) -> CGPoint {
        clampedOrigin(for: origin, size: size, in: visibleFrame(for: origin, itemSize: size))
    }

    private func clampedOrigin(for origin: CGPoint, size: CGSize, in frame: CGRect) -> CGPoint {
        let maxX = max(frame.minX, frame.maxX - size.width)
        let maxY = max(frame.minY, frame.maxY - size.height)

        return CGPoint(
            x: min(max(origin.x, frame.minX), maxX),
            y: min(max(origin.y, frame.minY), maxY)
        )
    }

    private func primaryVisibleFrame() -> CGRect {
        if let main = NSScreen.main?.visibleFrame {
            return main
        }

        if let first = NSScreen.screens.first?.visibleFrame {
            return first
        }

        return CGRect(x: 0, y: 0, width: 1280, height: 720)
    }

    private func visibleFrame(for origin: CGPoint, itemSize: CGSize) -> CGRect {
        let expandedFrames = NSScreen.screens.map { $0.visibleFrame.insetBy(dx: -itemSize.width, dy: -itemSize.height) }
        if let match = expandedFrames.first(where: { $0.contains(origin) }) {
            return match.insetBy(dx: itemSize.width, dy: itemSize.height)
        }

        return primaryVisibleFrame()
    }

    public func windowDidMove(_ notification: Notification) {
        persistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else {
                return
            }
            self.settingsStore.widgetOrigin = window.frame.origin
        }

        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}
