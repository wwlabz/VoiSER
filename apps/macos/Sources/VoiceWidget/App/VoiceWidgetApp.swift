import SwiftUI

@MainActor
final class VoiceWidgetAppModel: ObservableObject {
    let coordinator: VoiceWidgetCoordinator

    init() {
        coordinator = VoiceWidgetCoordinator.makeDefault()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            coordinator.bootstrap()
        }
    }
}

@main
struct VoiceWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = VoiceWidgetAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: appModel.coordinator)
        } label: {
            MenuBarLiveLabelView(coordinator: appModel.coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: appModel.coordinator)
        }
    }
}
