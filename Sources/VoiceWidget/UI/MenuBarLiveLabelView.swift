import SwiftUI

struct MenuBarLiveLabelView: View {
    @ObservedObject var coordinator: VoiceWidgetCoordinator

    var body: some View {
        Image(systemName: menuSymbol)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 18, height: 18)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.18), value: menuSymbol)
            .accessibilityLabel("VoiSER")
    }

    private var menuSymbol: String {
        switch coordinator.state {
        case .idle:
            return "mic"
        case .installingModel:
            return "arrow.down.circle"
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
