import CoreGraphics
import Foundation

@MainActor
public final class AppSettingsStore {
    private enum Keys {
        static let widgetOriginX = "widgetOriginX"
        static let widgetOriginY = "widgetOriginY"
        static let widgetOriginStored = "widgetOriginStored"
        static let widgetEnabled = "widgetEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let didRunInitialSetup = "didRunInitialSetup"
        static let preferredModel = "preferredModel"
        static let didChoosePreferredModel = "didChoosePreferredModel"
        static let didApplyPreferredModelMigration = "didApplyPreferredModelMigration"
        static let didCompleteRuntimeModelSetup = "didCompleteRuntimeModelSetup"
        static let hotkeyPreset = "hotkeyPreset"
        static let exclusiveSingleKeyEnabled = "exclusiveSingleKeyEnabled"
        static let exclusiveSingleKeyCode = "exclusiveSingleKeyCode"
        static let exclusiveSingleKeyCodeStored = "exclusiveSingleKeyCodeStored"
        static let exclusiveSingleKeyBlocksSystemDelivery = "exclusiveSingleKeyBlocksSystemDelivery"
        static let widgetStyle = "widgetStyle"
        static let textOutputMode = "textOutputMode"
        static let widgetPresentationMode = "widgetPresentationMode"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.widgetEnabled: true,
            Keys.launchAtLoginEnabled: true,
            Keys.didRunInitialSetup: false,
            Keys.preferredModel: WhisperModelOption.small.rawValue,
            Keys.didChoosePreferredModel: false,
            Keys.didApplyPreferredModelMigration: false,
            Keys.didCompleteRuntimeModelSetup: false,
            Keys.hotkeyPreset: HotkeyPreset.optionSpace.rawValue,
            Keys.exclusiveSingleKeyEnabled: false,
            Keys.exclusiveSingleKeyCodeStored: false,
            Keys.exclusiveSingleKeyBlocksSystemDelivery: true,
            Keys.widgetStyle: WidgetStyleOption.micOrb.rawValue,
            Keys.textOutputMode: TextOutputMode.clipboard.rawValue,
            Keys.widgetPresentationMode: WidgetPresentationMode.overlayOnly.rawValue
        ])

        applyMigrationsIfNeeded()
    }

    private func applyMigrationsIfNeeded() {
        guard !defaults.bool(forKey: Keys.didApplyPreferredModelMigration) else {
            return
        }

        // Legacy builds could persist a non-small model even if user never selected it.
        if !defaults.bool(forKey: Keys.didChoosePreferredModel) {
            defaults.set(WhisperModelOption.small.rawValue, forKey: Keys.preferredModel)
        }

        defaults.set(true, forKey: Keys.didApplyPreferredModelMigration)
    }

    public var widgetOrigin: CGPoint? {
        get {
            guard defaults.bool(forKey: Keys.widgetOriginStored) else {
                return nil
            }

            let x = defaults.double(forKey: Keys.widgetOriginX)
            let y = defaults.double(forKey: Keys.widgetOriginY)
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.set(false, forKey: Keys.widgetOriginStored)
                defaults.removeObject(forKey: Keys.widgetOriginX)
                defaults.removeObject(forKey: Keys.widgetOriginY)
                return
            }

            defaults.set(true, forKey: Keys.widgetOriginStored)
            defaults.set(newValue.x, forKey: Keys.widgetOriginX)
            defaults.set(newValue.y, forKey: Keys.widgetOriginY)
        }
    }

    public var widgetEnabled: Bool {
        get { defaults.bool(forKey: Keys.widgetEnabled) }
        set { defaults.set(newValue, forKey: Keys.widgetEnabled) }
    }

    public var launchAtLoginEnabled: Bool {
        get { defaults.bool(forKey: Keys.launchAtLoginEnabled) }
        set { defaults.set(newValue, forKey: Keys.launchAtLoginEnabled) }
    }

    public var didRunInitialSetup: Bool {
        get { defaults.bool(forKey: Keys.didRunInitialSetup) }
        set { defaults.set(newValue, forKey: Keys.didRunInitialSetup) }
    }

    public var preferredModel: WhisperModelOption {
        get {
            guard
                let raw = defaults.string(forKey: Keys.preferredModel),
                let value = WhisperModelOption(rawValue: raw)
            else {
                return .small
            }

            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.preferredModel)
            defaults.set(true, forKey: Keys.didChoosePreferredModel)
        }
    }

    public var hotkeyPreset: HotkeyPreset {
        get {
            guard
                let raw = defaults.string(forKey: Keys.hotkeyPreset),
                let value = HotkeyPreset(rawValue: raw)
            else {
                return .optionSpace
            }

            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.hotkeyPreset) }
    }

    public var exclusiveSingleKeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.exclusiveSingleKeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.exclusiveSingleKeyEnabled) }
    }

    public var exclusiveSingleKeyCode: Int? {
        get {
            guard defaults.bool(forKey: Keys.exclusiveSingleKeyCodeStored) else {
                return nil
            }
            return defaults.integer(forKey: Keys.exclusiveSingleKeyCode)
        }
        set {
            guard let newValue else {
                defaults.set(false, forKey: Keys.exclusiveSingleKeyCodeStored)
                defaults.removeObject(forKey: Keys.exclusiveSingleKeyCode)
                return
            }
            defaults.set(true, forKey: Keys.exclusiveSingleKeyCodeStored)
            defaults.set(newValue, forKey: Keys.exclusiveSingleKeyCode)
        }
    }

    public var exclusiveSingleKeyBlocksSystemDelivery: Bool {
        get { defaults.bool(forKey: Keys.exclusiveSingleKeyBlocksSystemDelivery) }
        set { defaults.set(newValue, forKey: Keys.exclusiveSingleKeyBlocksSystemDelivery) }
    }

    public var didCompleteRuntimeModelSetup: Bool {
        get { defaults.bool(forKey: Keys.didCompleteRuntimeModelSetup) }
        set { defaults.set(newValue, forKey: Keys.didCompleteRuntimeModelSetup) }
    }

    public var widgetStyle: WidgetStyleOption {
        get {
            guard
                let raw = defaults.string(forKey: Keys.widgetStyle),
                let value = WidgetStyleOption(rawValue: raw)
            else {
                return .micOrb
            }

            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.widgetStyle) }
    }

    public var textOutputMode: TextOutputMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.textOutputMode),
                let value = TextOutputMode(rawValue: raw)
            else {
                return .clipboard
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.textOutputMode) }
    }

    public var widgetPresentationMode: WidgetPresentationMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.widgetPresentationMode),
                let value = WidgetPresentationMode(rawValue: raw)
            else {
                return .overlayOnly
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.widgetPresentationMode) }
    }

    public func clearWidgetOrigin() {
        widgetOrigin = nil
    }
}
