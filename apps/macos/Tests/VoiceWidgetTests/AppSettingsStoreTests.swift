import CoreGraphics
import Foundation
import XCTest
@testable import VoiceWidget

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testWidgetOriginPersistence() {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertNil(store.widgetOrigin)

        let expected = CGPoint(x: 120, y: 80)
        store.widgetOrigin = expected

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.widgetOrigin?.x, expected.x)
        XCTAssertEqual(reloaded.widgetOrigin?.y, expected.y)

        reloaded.clearWidgetOrigin()
        XCTAssertNil(reloaded.widgetOrigin)
    }

    func testToggleValuesPersistence() {
        let suiteName = "AppSettingsStoreToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.widgetEnabled = false
        store.launchAtLoginEnabled = false
        store.didRunInitialSetup = true

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.widgetEnabled)
        XCTAssertFalse(reloaded.launchAtLoginEnabled)
        XCTAssertTrue(reloaded.didRunInitialSetup)
    }

    func testModelAndHotkeyPersistence() {
        let suiteName = "AppSettingsStoreModelHotkeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.preferredModel = .tiny
        store.hotkeyPreset = .commandShiftSpace
        store.exclusiveSingleKeyEnabled = true
        store.exclusiveSingleKeyCode = SingleKeyOption.f8.rawValue
        store.exclusiveSingleKeyBlocksSystemDelivery = false

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferredModel, .tiny)
        XCTAssertEqual(reloaded.hotkeyPreset, .commandShiftSpace)
        XCTAssertTrue(reloaded.exclusiveSingleKeyEnabled)
        XCTAssertEqual(reloaded.exclusiveSingleKeyCode, SingleKeyOption.f8.rawValue)
        XCTAssertFalse(reloaded.exclusiveSingleKeyBlocksSystemDelivery)
    }

    func testStyleAndOutputModePersistence() {
        let suiteName = "AppSettingsStoreStyleOutputTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = AppSettingsStore(defaults: defaults)
        store.widgetStyle = .voiceBar
        store.textOutputMode = .pasteStrict
        store.widgetPresentationMode = .menuBarAndOverlay

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.widgetStyle, .voiceBar)
        XCTAssertEqual(reloaded.textOutputMode, .pasteStrict)
        XCTAssertEqual(reloaded.widgetPresentationMode, .menuBarAndOverlay)
    }

    func testLegacyModelMigratesToSmallWhenNotExplicitlyChosen() {
        let suiteName = "AppSettingsStoreModelMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(WhisperModelOption.base.rawValue, forKey: "preferredModel")
        defaults.set(false, forKey: "didChoosePreferredModel")
        defaults.set(false, forKey: "didApplyPreferredModelMigration")

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.preferredModel, .small)
    }
}
