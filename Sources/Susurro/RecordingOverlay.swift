import AppKit

enum OverlayMode { case recording, processing }

/// A floating, non-activating pill near the bottom of the screen that shows recording /
/// processing state with a live audio-reactive equalizer. It never becomes key and ignores
/// mouse events, so it never steals focus from the app receiving the dictated text.
final class RecordingOverlay {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel: Panel
    private let waveform: WaveformView
    private let dot: NSView
    private var timer: Timer?
    private var targetLevel: CGFloat = 0
    private var smoothedLevel: CGFloat = 0
    private var pulse: CGFloat = 0
    private var mode: OverlayMode = .recording
    private var generation = 0

    init() {
        let size = NSSize(width: 132, height: 40)
        panel = Panel(contentRect: NSRect(origin: .zero, size: size),
                      styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered,
                      defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = size.height / 2
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        dot = NSView(frame: NSRect(x: 18, y: size.height / 2 - 5, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor

        waveform = WaveformView(frame: NSRect(x: 38, y: 0, width: size.width - 54, height: size.height))
        waveform.autoresizingMask = [.width, .height]

        effect.addSubview(dot)
        effect.addSubview(waveform)
        panel.contentView = effect
    }

    func showRecording() {
        mode = .recording
        waveform.mode = .recording
        targetLevel = 0
        smoothedLevel = 0
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        present()
    }

    func showProcessing() {
        mode = .processing
        waveform.mode = .processing
        dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
    }

    func update(level rms: Float) {
        // Map RMS to a perceptual dB scale so normal-volume speech fills most of the range
        // instead of barely registering (loudness is logarithmic, not linear).
        let db = 20 * log10(max(rms, 1e-7))
        let floor: Float = -52
        let ceiling: Float = -20
        let normalized = max(0, min(1, (db - floor) / (ceiling - floor)))
        DispatchQueue.main.async { [weak self] in
            self?.targetLevel = CGFloat(normalized)
        }
    }

    func hide() {
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A new recording may have presented the panel while the fade-out ran;
            // only the latest transition gets to tear it down.
            guard let self, self.generation == token else { return }
            self.panel.orderOut(nil)
            self.stopTimer()
        })
    }

    private func present() {
        generation += 1
        positionPanel()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        startTimer()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 140))
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        smoothedLevel += (targetLevel - smoothedLevel) * 0.35
        if mode == .processing {
            smoothedLevel += (0.45 - smoothedLevel) * 0.10
        }
        waveform.level = smoothedLevel
        waveform.advance()

        pulse += 0.12
        let alpha: CGFloat = mode == .recording ? (0.55 + 0.45 * (sin(pulse) + 1) / 2) : 0.6
        dot.layer?.opacity = Float(alpha)
    }
}

private final class WaveformView: NSView {
    var level: CGFloat = 0
    var mode: OverlayMode = .recording

    private let barCount = 5
    private let phases: [CGFloat]
    private var tick: CGFloat = 0

    override init(frame frameRect: NSRect) {
        phases = (0..<barCount).map { CGFloat($0) * 0.7 }
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func advance() {
        tick += 0.20
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 4
        let gap: CGFloat = 5
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let midY = bounds.height / 2
        let maxBar = bounds.height * 0.72

        NSColor.white.setFill()
        for index in 0..<barCount {
            let wave = (sin(tick + phases[index]) + 1) / 2
            let amplitude: CGFloat
            switch mode {
            case .recording:
                amplitude = max(0.12, min(1, level)) * (0.5 + 0.5 * wave)
            case .processing:
                amplitude = 0.25 + 0.45 * wave
            }
            let height = max(barWidth, maxBar * amplitude)
            let x = startX + CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
