import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var coordinator: VoiceWidgetCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(coordinator.primaryActionTitle) {
                coordinator.toggleCapture()
            }
            .disabled(coordinator.isPrimaryActionDisabled)

            Toggle(
                "Показывать overlay",
                isOn: Binding(
                    get: { coordinator.widgetEnabled },
                    set: { coordinator.setWidgetEnabled($0) }
                )
            )

            Divider()

            Button("Проверить разрешения") {
                coordinator.runPermissionsOnboarding()
            }

            SettingsLink {
                Text("Настройки")
            }

            Button("Выйти") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 220)
    }
}
