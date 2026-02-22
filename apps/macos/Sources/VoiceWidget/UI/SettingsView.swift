import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: VoiceWidgetCoordinator
    @State private var isCapturingSingleKey = false
    @State private var keyCaptureMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                appearanceSection
                outputSection
                presentationSection
                controlsSection
                recognitionSection
                behaviorSection
                maintenanceSection
                errorSection
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: 520, height: 620)
        .onDisappear {
            stopSingleKeyCapture()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Настройки VoiSER")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Внешний вид, распознавание и способ вывода текста")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceSection: some View {
        settingsCard("Внешний вид виджета", icon: "paintbrush") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Выберите стиль кнопки")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(WidgetStyleOption.allCases, id: \.self) { style in
                        styleCard(style)
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        settingsCard("Вывод текста", icon: "text.cursor") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TextOutputMode.allCases, id: \.self) { mode in
                    Button {
                        coordinator.setTextOutputMode(mode)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode == coordinator.textOutputMode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(mode == coordinator.textOutputMode ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.system(size: 13, weight: .semibold))
                                Text(mode.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var presentationSection: some View {
        settingsCard("Показ виджета", icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(WidgetPresentationMode.allCases, id: \.self) { mode in
                    Button {
                        coordinator.setWidgetPresentationMode(mode)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode == coordinator.widgetPresentationMode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(mode == coordinator.widgetPresentationMode ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.system(size: 13, weight: .semibold))
                                Text(mode.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlsSection: some View {
        settingsCard("Управление", icon: "keyboard") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Пресет хоткея") {
                    hotkeyMenu
                }
                KeyboardShortcuts.Recorder("Горячая клавиша записи", name: .toggleRecording)

                Divider()

                Toggle(
                    "Режим одной клавиши",
                    isOn: Binding(
                        get: { coordinator.exclusiveSingleKeyEnabled },
                        set: { coordinator.setExclusiveSingleKeyEnabled($0) }
                    )
                )

                if coordinator.exclusiveSingleKeyEnabled {
                    LabeledContent("Клавиша") {
                        Button {
                            if isCapturingSingleKey {
                                stopSingleKeyCapture()
                            } else {
                                startSingleKeyCapture()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(isCapturingSingleKey ? "Нажмите клавишу…" : coordinator.exclusiveSingleKeyTitle)
                                    .fontWeight(.semibold)
                                if isCapturingSingleKey {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Toggle(
                        "Блокировать эту клавишу в других приложениях",
                        isOn: Binding(
                            get: { coordinator.exclusiveSingleKeyBlocksSystemDelivery },
                            set: { coordinator.setExclusiveSingleKeyBlocksSystemDelivery($0) }
                        )
                    )

                    Text("Для режима одной клавиши требуется разрешение Input Monitoring. Без него режим не активируется.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if isCapturingSingleKey {
                        Text("Нажмите одну клавишу без модификаторов. Привязка по физической клавише, не зависит от раскладки.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recognitionSection: some View {
        settingsCard("Распознавание", icon: "waveform") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Модель Whisper") {
                    modelMenu
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.isModelReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(coordinator.isModelReady ? "Модель готова" : "Модель не подготовлена")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let message = coordinator.modelPreparationMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: coordinator.modelPreparationProgress)
                            .progressViewStyle(.linear)
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        settingsCard("Поведение приложения", icon: "switch.2") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Показывать виджет",
                    isOn: Binding(
                        get: { coordinator.widgetEnabled },
                        set: { coordinator.setWidgetEnabled($0) }
                    )
                )

                Toggle(
                    "Запускать при входе в систему",
                    isOn: Binding(
                        get: { coordinator.launchAtLoginEnabled },
                        set: { coordinator.setLaunchAtLoginEnabled($0) }
                    )
                )
            }
        }
    }

    private var maintenanceSection: some View {
        settingsCard("Обслуживание", icon: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 8) {
                Button("Сбросить позицию виджета") {
                    coordinator.resetWidgetPosition()
                }
                Button("Проверить разрешения вставки") {
                    coordinator.runPermissionsOnboarding()
                }
                Button("Переинициализировать модель") {
                    coordinator.retryModelLoad()
                }
                Button("Установить / обновить модель") {
                    coordinator.prepareModelNow()
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = coordinator.lastError {
            settingsCard("Ошибка", icon: "exclamationmark.triangle") {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.system(size: 12, weight: .medium))
                    .textSelection(.enabled)
            }
        }
    }

    private func styleCard(_ style: WidgetStyleOption) -> some View {
        let isSelected = coordinator.widgetStyle == style

        return Button {
            coordinator.setWidgetStyle(style)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                    Image(systemName: style.symbolName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(height: 54)

                Text(style.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(style.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var hotkeyMenu: some View {
        Menu {
            ForEach(HotkeyPreset.allCases, id: \.self) { preset in
                Button {
                    coordinator.setHotkeyPreset(preset)
                } label: {
                    if preset == coordinator.hotkeyPreset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
        } label: {
            menuLabel(coordinator.hotkeyPreset.title)
        }
        .menuStyle(.borderlessButton)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(WhisperModelOption.allCases, id: \.self) { model in
                Button {
                    coordinator.setPreferredModel(model)
                } label: {
                    if model == coordinator.preferredModel {
                        Label(model.title, systemImage: "checkmark")
                    } else {
                        Text(model.title)
                    }
                }
            }
        } label: {
            menuLabel(coordinator.preferredModel.title)
        }
        .menuStyle(.borderlessButton)
    }

    private func startSingleKeyCapture() {
        stopSingleKeyCapture()
        isCapturingSingleKey = true

        keyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
            if !event.modifierFlags.intersection(modifiers).isEmpty {
                return event
            }

            let keyCode = Int(event.keyCode)
            coordinator.setExclusiveSingleKeyCode(keyCode)
            stopSingleKeyCapture()
            return nil
        }
    }

    private func stopSingleKeyCapture() {
        if let keyCaptureMonitor {
            NSEvent.removeMonitor(keyCaptureMonitor)
            self.keyCaptureMonitor = nil
        }
        isCapturingSingleKey = false
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
