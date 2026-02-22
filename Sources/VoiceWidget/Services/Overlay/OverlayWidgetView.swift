import AppKit
import SwiftUI

private struct MotionPhases {
    let elapsed: TimeInterval
    let slow: CGFloat
    let medium: CGFloat
    let fast: CGFloat
    let sweep: CGFloat
}

struct OverlayWidgetView: View {
    @ObservedObject var viewModel: OverlayWidgetViewModel

    let onTap: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onResetPosition: () -> Void
    let onSelectModel: (WhisperModelOption) -> Void
    let onSelectHotkey: (HotkeyPreset) -> Void
    let onSelectStyle: (WidgetStyleOption) -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var isDragging = false
    @State private var isPressed = false
    @State private var timelineOrigin = Date()
    @State private var failedSince: Date?

    private let dragThreshold: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { context in
            let phases = phases(at: context.date)
            root(phases)
        }
        .onAppear {
            timelineOrigin = Date()
            syncFailureStart(for: viewModel.state)
        }
        .onChange(of: viewModel.state, initial: false) { _, newState in
            syncFailureStart(for: newState)
        }
        .contextMenu {
            Button(action: onTap) {
                Label(viewModel.state == .recording ? "Остановить запись" : "Начать запись", systemImage: "mic.fill")
            }

            Picker(
                "Модель распознавания",
                selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { onSelectModel($0) }
                )
            ) {
                ForEach(WhisperModelOption.allCases, id: \.self) { model in
                    Text(model.title).tag(model)
                }
            }

            Picker(
                "Горячая клавиша",
                selection: Binding(
                    get: { viewModel.hotkeyPreset },
                    set: { onSelectHotkey($0) }
                )
            ) {
                ForEach(HotkeyPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Picker(
                "Стиль виджета",
                selection: Binding(
                    get: { viewModel.widgetStyle },
                    set: { onSelectStyle($0) }
                )
            ) {
                ForEach(WidgetStyleOption.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }

            Divider()

            Button("Настройки…", action: onOpenSettings)
            Button("Сбросить позицию", action: onResetPosition)
            Button("Выйти") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func root(_ phases: MotionPhases) -> some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topTrailing) {
                avatar(phases)

                if viewModel.canRetryModel {
                    retryButton
                }
            }
            .frame(width: max(100, avatarSize.width + 20), height: max(92, avatarSize.height + 20))
            .offset(y: 18)

            if let message = viewModel.message {
                messageBubble(message)
                    .id(message)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .offset(y: 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: max(132, avatarSize.width + 38), height: 132)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.state)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.message)
        .animation(.easeInOut(duration: 0.22), value: viewModel.widgetStyle)
    }

    private func avatar(_ phases: MotionPhases) -> some View {
        styleView(phases)
            .id(viewModel.widgetStyle)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .frame(width: avatarSize.width, height: avatarSize.height)
            .compositingGroup()
            .offset(x: failureShakeOffset(at: phases.elapsed))
            .scaleEffect(isPressed ? 0.96 : (isDragging ? 1.03 : 1.0))
            .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 4)
            .overlay(
                IconInteractionSurface(
                    dragThreshold: dragThreshold,
                    onTap: onTap,
                    onDragBegan: {
                        isDragging = true
                        isPressed = false
                        onDragBegan()
                    },
                    onDragChanged: onDragChanged,
                    onDragEnded: {
                        onDragEnded()
                        isDragging = false
                        isPressed = false
                    },
                    onPressChanged: { isPressed = $0 }
                )
                .clipShape(RoundedRectangle(cornerRadius: interactionCornerRadius, style: .continuous))
            )
            .help("Нажми для записи или перетащи за весь значок.")
    }

    private func styleView(_ phases: MotionPhases) -> some View {
        Group {
            switch viewModel.widgetStyle {
            case .micOrb:
                micOrbStyle(phases)
            case .voiceBar:
                voiceBarStyle(phases)
            case .pulseDot:
                pulseDotStyle(phases)
            case .notchTop:
                notchTopStyle(phases)
            }
        }
    }

    private func micOrbStyle(_ phases: MotionPhases) -> some View {
        let shape = Circle()
        return ZStack {
            micOrbBase(shape, phases: phases)
            micOrbRecordingLayer(shape, phases: phases)
            micOrbTranscribingLayer(shape, phases: phases)
            micOrbFailureLayer(shape)
            micOrbIcon
        }
        .compositingGroup()
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func micOrbBase(_ shape: Circle, phases: MotionPhases) -> some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: gradientColors(for: viewModel.state),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(stateAccent.opacity(0.22))
                .blur(radius: 12 + (12 * reactiveLevel))
                .scaleEffect(0.84 + (0.16 * breathing(phases)))

            shape
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.4), .clear],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 34
                    )
                )
                .offset(x: -8, y: -8)

            shape
                .stroke(Color.white.opacity(0.14), lineWidth: 2)
                .scaleEffect(0.96 + (0.08 * breathing(phases)))
                .opacity(0.35 + (0.16 * breathing(phases)))
        }
    }

    @ViewBuilder
    private func micOrbRecordingLayer(_ shape: Circle, phases: MotionPhases) -> some View {
        if case .recording = viewModel.state {
            shape
                .stroke(Color.white.opacity(0.68), lineWidth: 2)
                .scaleEffect(1.04 + (0.22 * reactiveLevel) + (0.08 * pulse(phases)))
                .opacity(0.62 - (0.3 * reactiveLevel))

            shape
                .stroke(Color.white.opacity(0.34), lineWidth: 1.5)
                .scaleEffect(1.2 + (0.18 * reactiveLevel) + (0.06 * pulse(phases)))
                .opacity(0.34 - (0.2 * reactiveLevel))
        }
    }

    @ViewBuilder
    private func micOrbTranscribingLayer(_ shape: Circle, phases: MotionPhases) -> some View {
        if case .transcribing = viewModel.state {
            shape
                .trim(from: 0.06, to: 0.64)
                .stroke(
                    AngularGradient(
                        colors: [Color.white.opacity(0.2), Color.white, Color.white.opacity(0.2)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
                .scaleEffect(1.08)
                .rotationEffect(.degrees(360 * Double(phases.fast)))

            shape
                .trim(from: 0.42, to: 0.88)
                .stroke(Color.white.opacity(0.46), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2, 3]))
                .scaleEffect(1.16)
                .rotationEffect(.degrees(-280 * Double(phases.fast)))
        }
    }

    @ViewBuilder
    private func micOrbFailureLayer(_ shape: Circle) -> some View {
        if case .failed = viewModel.state {
            shape
                .fill(Color.black.opacity(0.24))
                .padding(16)
        }
    }

    private var micOrbIcon: some View {
        Image(systemName: symbolName(for: viewModel.state))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.14), radius: 1, x: 0, y: 1)
            .scaleEffect(1 + (0.06 * reactiveLevel))
    }

    private func voiceBarStyle(_ phases: MotionPhases) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: barBackgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: barColors,
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4.7, height: barHeight(for: index, phases: phases))
                        .shadow(color: stateAccent.opacity(0.24), radius: 2, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 14)

            if case .transcribing = viewModel.state {
                shape
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.32), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: (phases.sweep * 88) - 44)
            }

            if case .failed = viewModel.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .compositingGroup()
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func pulseDotStyle(_ phases: MotionPhases) -> some View {
        let shape = Circle()
        let orbitAngle = (Double(phases.fast) * 2 * Double.pi)
        let orbitRadius: CGFloat = 18
        let orbitX = cos(orbitAngle) * orbitRadius
        let orbitY = sin(orbitAngle) * orbitRadius

        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.09, blue: 0.18), Color(red: 0.03, green: 0.13, blue: 0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shape
                .fill(stateAccent.opacity(0.2))
                .blur(radius: 10 + (10 * reactiveLevel))
                .scaleEffect(0.84 + (0.18 * breathing(phases)))

            shape
                .fill(stateAccent)
                .frame(width: 22 + (14 * reactiveLevel), height: 22 + (14 * reactiveLevel))
                .blur(radius: 0.5 + (1.2 * reactiveLevel))

            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 10, height: 10)

            if case .recording = viewModel.state {
                shape
                    .stroke(Color.white.opacity(0.62), lineWidth: 1.8)
                    .scaleEffect(1.2 + (0.28 * reactiveLevel) + (0.08 * pulse(phases)))
                    .opacity(0.7 - (0.38 * reactiveLevel))
            }

            if case .transcribing = viewModel.state {
                shape
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    .padding(8)

                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .offset(x: orbitX, y: orbitY)
                    .shadow(radius: 2)
            }

            if case .failed = viewModel.state {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }

            if case .installingModel = viewModel.state {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.75)
            }
        }
        .compositingGroup()
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func notchTopStyle(_ phases: MotionPhases) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.88), Color.black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            shape
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            HStack(spacing: 8) {
                Image(systemName: symbolName(for: viewModel.state))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 14)

                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 3, height: notchBarHeight(for: index, phases: phases))
                    }
                }
                .opacity(viewModel.state == .idle ? 0.46 : 1.0)
            }
        }
        .clipShape(shape)
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(
                    Circle()
                        .fill(.black.opacity(0.66))
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .help("Переинициализировать модель")
    }

    private func messageBubble(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(2)
    }

    private var avatarSize: CGSize {
        switch viewModel.widgetStyle {
        case .micOrb:
            CGSize(width: 82, height: 82)
        case .voiceBar:
            CGSize(width: 98, height: 58)
        case .pulseDot:
            CGSize(width: 74, height: 74)
        case .notchTop:
            CGSize(width: 96, height: 36)
        }
    }

    private var interactionCornerRadius: CGFloat {
        switch viewModel.widgetStyle {
        case .voiceBar:
            return 22
        case .notchTop:
            return 18
        case .micOrb, .pulseDot:
            return 42
        }
    }

    private var stateAccent: Color {
        gradientColors(for: viewModel.state).first ?? Color.blue
    }

    private var barBackgroundColors: [Color] {
        switch viewModel.state {
        case .idle:
            [Color(red: 0.06, green: 0.12, blue: 0.26), Color(red: 0.04, green: 0.18, blue: 0.32)]
        case .installingModel:
            [Color(red: 0.1, green: 0.16, blue: 0.2), Color(red: 0.09, green: 0.21, blue: 0.29)]
        case .recording:
            [Color(red: 0.34, green: 0.06, blue: 0.2), Color(red: 0.62, green: 0.08, blue: 0.24)]
        case .transcribing:
            [Color(red: 0.08, green: 0.24, blue: 0.42), Color(red: 0.09, green: 0.35, blue: 0.62)]
        case .failed:
            [Color(red: 0.34, green: 0.17, blue: 0.06), Color(red: 0.56, green: 0.26, blue: 0.04)]
        }
    }

    private var barColors: [Color] {
        switch viewModel.state {
        case .installingModel:
            [Color.white.opacity(0.9), Color(red: 0.58, green: 0.84, blue: 1.0)]
        case .recording:
            [Color.white.opacity(0.94), Color(red: 1.0, green: 0.42, blue: 0.55)]
        case .transcribing:
            [Color.white.opacity(0.95), Color(red: 0.47, green: 0.79, blue: 1.0)]
        case .failed:
            [Color(red: 1.0, green: 0.85, blue: 0.42), Color(red: 1.0, green: 0.56, blue: 0.22)]
        case .idle:
            [Color.white.opacity(0.86), Color.white.opacity(0.68)]
        }
    }

    private var reactiveLevel: CGFloat {
        let input = CGFloat(max(0, min(1, viewModel.inputLevelSmoothed)))
        switch viewModel.state {
        case .recording:
            return max(input, 0.11)
        case .installingModel:
            return 0.14
        case .transcribing:
            return 0.2
        case .failed:
            return 0.08
        case .idle:
            return 0.06
        }
    }

    private func barHeight(for index: Int, phases: MotionPhases) -> CGFloat {
        let centeredDistance = abs(CGFloat(index) - 4)
        let base = 9 + max(0, (4 - centeredDistance)) * 1.8
        let wave = sin((Double(phases.medium) * 2 * .pi) + (Double(index) * 0.55))

        switch viewModel.state {
        case .idle:
            return min(42, max(8, base + (CGFloat(wave) * 2.2) + (1.8 * breathing(phases))))
        case .installingModel:
            let installWave = sin((Double(phases.fast) * 2 * .pi) + (Double(index) * 0.65))
            return min(42, max(8, 11 + (CGFloat(installWave + 1) * 5.4)))
        case .recording:
            let lift = reactiveLevel * (23 - centeredDistance * 2.3)
            return min(42, max(9, base + lift + (CGFloat(wave) * 1.8)))
        case .transcribing:
            let transcribeWave = sin((Double(phases.fast) * 2 * .pi * 1.7) + (Double(index) * 0.8))
            return min(42, max(8, 10 + (CGFloat(transcribeWave + 1) * 8.2)))
        case .failed:
            return min(42, max(8, 10 + CGFloat(index % 2 == 0 ? 2 : 6) + (1.8 * pulse(phases))))
        }
    }

    private func notchBarHeight(for index: Int, phases: MotionPhases) -> CGFloat {
        let wave = sin((Double(phases.fast) * 2 * .pi * 1.4) + (Double(index) * 0.72))
        switch viewModel.state {
        case .idle:
            return 7 + CGFloat((wave + 1) * 0.8)
        case .installingModel:
            return 8 + CGFloat((wave + 1) * 1.8)
        case .recording:
            return 8 + CGFloat((wave + 1) * 2.8) + (reactiveLevel * 5)
        case .transcribing:
            return 8 + CGFloat((wave + 1) * 2.2)
        case .failed:
            return 9
        }
    }

    private func phases(at date: Date) -> MotionPhases {
        let elapsed = max(0, date.timeIntervalSince(timelineOrigin))

        func fraction(_ duration: TimeInterval) -> CGFloat {
            guard duration > 0 else { return 0 }
            let value = elapsed.truncatingRemainder(dividingBy: duration) / duration
            return CGFloat(value)
        }

        return MotionPhases(
            elapsed: elapsed,
            slow: fraction(6.0),
            medium: fraction(2.0),
            fast: fraction(1.0),
            sweep: fraction(0.9)
        )
    }

    private func breathing(_ phases: MotionPhases) -> CGFloat {
        let value = (sin(Double(phases.slow) * 2 * .pi) + 1) / 2
        return CGFloat(value)
    }

    private func pulse(_ phases: MotionPhases) -> CGFloat {
        let value = (sin(Double(phases.medium) * 2 * .pi) + 1) / 2
        return CGFloat(value)
    }

    private func failureShakeOffset(at elapsed: TimeInterval) -> CGFloat {
        guard case .failed = viewModel.state, let failedSince else {
            return 0
        }

        let dt = max(0, elapsed - failedSince.timeIntervalSince(timelineOrigin))
        guard dt < 0.30 else {
            return 0
        }

        let decay = exp(-dt * 11)
        return CGFloat(sin(dt * 68) * 4 * decay)
    }

    private func syncFailureStart(for state: CaptureState) {
        if case .failed = state {
            if failedSince == nil {
                failedSince = Date()
            }
        } else {
            failedSince = nil
        }
    }

    private func symbolName(for state: CaptureState) -> String {
        switch state {
        case .idle:
            "mic.fill"
        case .installingModel:
            "arrow.down.circle.fill"
        case .recording:
            "stop.fill"
        case .transcribing:
            "waveform"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func gradientColors(for state: CaptureState) -> [Color] {
        switch state {
        case .idle:
            [Color(red: 0.08, green: 0.16, blue: 0.34), Color(red: 0.05, green: 0.26, blue: 0.42)]
        case .installingModel:
            [Color(red: 0.21, green: 0.38, blue: 0.59), Color(red: 0.08, green: 0.24, blue: 0.38)]
        case .recording:
            [Color(red: 0.95, green: 0.2, blue: 0.34), Color(red: 0.64, green: 0.07, blue: 0.26)]
        case .transcribing:
            [Color(red: 0.23, green: 0.55, blue: 1.0), Color(red: 0.1, green: 0.31, blue: 0.76)]
        case .failed:
            [Color(red: 0.88, green: 0.56, blue: 0.13), Color(red: 0.61, green: 0.29, blue: 0.06)]
        }
    }
}

private struct IconInteractionSurface: NSViewRepresentable {
    let dragThreshold: CGFloat
    let onTap: () -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onPressChanged: (Bool) -> Void

    func makeNSView(context: Context) -> IconInteractionView {
        let view = IconInteractionView()
        view.onTap = onTap
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onPressChanged = onPressChanged
        view.dragThreshold = dragThreshold
        return view
    }

    func updateNSView(_ nsView: IconInteractionView, context: Context) {
        nsView.onTap = onTap
        nsView.onDragBegan = onDragBegan
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onPressChanged = onPressChanged
        nsView.dragThreshold = dragThreshold
    }
}

private final class IconInteractionView: NSView {
    var onTap: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    var dragThreshold: CGFloat = 5

    private var startScreenPoint: CGPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        startScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
        isDragging = false
        onPressChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startScreenPoint else {
            return
        }

        let current = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = current.x - startScreenPoint.x
        let deltaY = current.y - startScreenPoint.y
        let distance = hypot(deltaX, deltaY)

        if distance > dragThreshold {
            if !isDragging {
                isDragging = true
                onPressChanged?(false)
                onDragBegan?()
            }

            // Keep compatibility with existing window controller math (down is +Y).
            onDragChanged?(CGSize(width: deltaX, height: -deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startScreenPoint = nil
            isDragging = false
            onPressChanged?(false)
        }

        if isDragging {
            onDragEnded?()
        } else {
            onTap?()
        }
    }
}
