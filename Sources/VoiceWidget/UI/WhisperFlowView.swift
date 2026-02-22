import SwiftUI

struct WhisperFlowView: View {
    @ObservedObject var coordinator: VoiceWidgetCoordinator

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.9, green: 0.92, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(14)

            VStack(alignment: .leading, spacing: 18) {
                header
                steps
                progressCard
                actions
            }
            .padding(30)
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VoiSER Setup")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.2))
            Text("Для первого запуска нужна локальная Whisper-модель. После установки всё работает офлайн.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.62))
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            stepTag(index: 1, title: "Скачать модель", active: !coordinator.isModelReady)
            stepTag(index: 2, title: "Разрешения", active: coordinator.isModelReady)
            stepTag(index: 3, title: "Готово", active: coordinator.isModelReady)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progressTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                Spacer(minLength: 0)
                Text("\(Int(max(0, min(1, coordinator.modelPreparationProgress)) * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.22, blue: 0.34))
            }

            ProgressView(value: coordinator.modelPreparationProgress)
                .tint(Color(red: 0.16, green: 0.22, blue: 0.34))
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 1.15, anchor: .center)

            if let error = coordinator.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.62, green: 0.2, blue: 0.2))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        )
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(primaryButtonTitle) {
                coordinator.prepareModelNow()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.16, green: 0.22, blue: 0.34))
            )
            .opacity(coordinator.canStartModelDownload ? 1 : 0.55)
            .disabled(!coordinator.canStartModelDownload)

            Spacer(minLength: 0)

            Text("VoiSER")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.38))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
        }
    }

    private func stepTag(index: Int, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 18, height: 18)
                .background(Circle().fill(active ? Color.black.opacity(0.16) : Color.black.opacity(0.06)))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(active ? Color.black.opacity(0.78) : Color.black.opacity(0.44))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(active ? Color.white.opacity(0.85) : Color.white.opacity(0.45))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.black.opacity(active ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    private var progressTitle: String {
        coordinator.modelPreparationMessage ?? "Ожидание установки модели"
    }

    private var primaryButtonTitle: String {
        coordinator.isModelReady ? "Модель готова" : "Скачать модель"
    }
}
