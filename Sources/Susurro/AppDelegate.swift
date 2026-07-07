import AppKit
import AVFoundation
import ApplicationServices
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }

    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private let overlay = RecordingOverlay()
    private let settings = SettingsWindowController()
    private let onboarding = OnboardingWindowController()
    private var config = Config.load()

    /// Sparkle only works inside an .app bundle; in development runs (`swift build` + bare
    /// binary) it stays unstarted and its menu item is a no-op.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.bundleIdentifier != nil,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private lazy var idleIcon = Self.barsImage(color: .black, template: true)
    private lazy var recordingIcon = Self.barsImage(color: .systemRed, template: false)
    private lazy var errorIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                         accessibilityDescription: "Susurro error")
    /// Hidden until a dictation fails; then it tells what happened and when, because the
    /// ⚠️ flash alone is mute and the NSLog detail gets redacted in the unified log.
    private let lastErrorItem = NSMenuItem()

    /// Single source of truth for the dictation pipeline. Driving the menu-bar icon and the
    /// overlay from here keeps them in sync, and makes stray hotkey events (like a tap while
    /// a previous dictation is still processing) harmless no-ops.
    private var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            statusItem.button?.image = state == .recording ? recordingIcon : idleIcon
            switch state {
            case .idle: overlay.hide()
            case .recording: overlay.showRecording()
            case .processing: overlay.showProcessing()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.writeTemplateIfMissing()
        setupStatusItem()

        recorder.onLevel = { [weak self] level in self?.overlay.update(level: level) }
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndProcess() }
        hotkey.start()

        if onboardingNeeded { showOnboarding() }
    }

    /// Reopening the app (from Raycast, Spotlight or the Dock) has no main window to restore,
    /// so we surface the onboarding while setup is incomplete, or the settings otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingNeeded {
            showOnboarding()
        } else {
            openSettings()
        }
        return true
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = idleIcon

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let menu = NSMenu()
        menu.addItem(disabled: version.map { "Susurro \($0)" } ?? "Susurro")
        menu.addItem(.separator())
        menu.addItem(disabled: "Mantén ⌥ (Option derecho) para dictar")
        lastErrorItem.isEnabled = false
        lastErrorItem.isHidden = true
        menu.addItem(lastErrorItem)
        menu.addItem(.separator())
        menu.addItem(action: "Configuración…", #selector(openSettings), target: self, key: ",")
        menu.addItem(action: "Buscar actualizaciones…",
                     #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                     target: updater, key: "")
        menu.addItem(.separator())
        menu.addItem(action: "Salir", #selector(NSApplication.terminate(_:)), target: nil, key: "q")
        statusItem.menu = menu
    }

    /// The Susurro equalizer motif rendered as a menu-bar glyph. As a template image it adapts
    /// to a light or dark menu bar; the red, non-template variant signals active recording.
    private static func barsImage(color: NSColor, template: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let heights: [CGFloat] = [0.34, 0.60, 0.90, 0.60, 0.34]
            let barWidth: CGFloat = 2.2
            let gap: CGFloat = 2.0
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let startX = (rect.width - totalWidth) / 2
            let maxBar = rect.height * 0.82
            let midY = rect.height / 2
            color.setFill()
            for (index, fraction) in heights.enumerated() {
                let height = maxBar * fraction
                let x = startX + CGFloat(index) * (barWidth + gap)
                let bar = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    // MARK: - Onboarding

    /// Everything a fresh install must have before dictation can work.
    private var onboardingNeeded: Bool {
        !config.hasKey
            || !AXIsProcessTrusted()
            || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
    }

    private func showOnboarding() {
        onboarding.show(hasKey: config.hasKey) { [weak self] key in
            guard let self else { return }
            var updated = self.config
            updated.groqApiKey = key
            do {
                try updated.save()
                self.config = updated
            } catch {
                NSLog("[Susurro] failed to save config: \(error)")
            }
        }
    }

    // MARK: - Recording pipeline

    private func startRecording() {
        guard state == .idle else { return }
        do {
            try recorder.start()
            state = .recording
        } catch {
            NSLog("[Susurro] record start failed: \(error)")
        }
    }

    private func stopAndProcess() {
        guard state == .recording else { return }
        guard let recording = recorder.stop() else {
            state = .idle
            return
        }
        guard recording.hasSpeech else {
            NSLog("[Susurro] discarded speechless recording (%.2fs, peak %.4f, active %.2fs)",
                  recording.duration, recording.peakLevel, recording.activeDuration)
            recording.removeFile()
            state = .idle
            return
        }
        state = .processing

        let pipeline = DictationPipeline(config: config)
        // Captured now, while the caret is still where the text will land.
        let context = config.useCursorContext ? FocusContext.textBeforeCaret() : nil
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let technical = frontApp.map(config.technicalApps.contains) ?? false

        Task {
            let outcome = await pipeline.run(recording: recording, context: context, technical: technical)
            await MainActor.run { self.finish(with: outcome) }
        }
    }

    /// The only place a dictation outcome becomes UI.
    @MainActor
    private func finish(with outcome: DictationOutcome) {
        state = .idle
        switch outcome {
        case .injected, .empty:
            break
        case .clipboardOnly:
            // The text survives on the clipboard; the checklist window shows exactly
            // which permission died and fixes it in one click.
            showOnboarding()
        case .failed(let error):
            NSLog("[Susurro] pipeline failed: \(error.localizedDescription)")
            showLastError(Self.describe(error))
            flashErrorIcon()
        }
    }

    private func showLastError(_ description: String) {
        let time = Date().formatted(date: .omitted, time: .shortened)
        lastErrorItem.title = "⚠️ \(time) \(description)"
        lastErrorItem.isHidden = false
    }

    /// The one line of truth a user can act on, in the app's language.
    private static func describe(_ error: Error) -> String {
        switch error {
        case GroqClient.ClientError.http(401, _):
            return "La API key de Groq no es válida"
        case let GroqClient.ClientError.http(429, body):
            return body.contains("per day") || body.contains("TPD")
                ? "Cuota diaria de Groq agotada, se recupera sola en unas horas"
                : "Groq saturado, prueba de nuevo en unos segundos"
        case let GroqClient.ClientError.http(code, _):
            return "Groq devolvió HTTP \(code)"
        case is URLError:
            return "Sin conexión con Groq"
        default:
            return error.localizedDescription
        }
    }

    /// Brief ⚠️ in the menu bar: enough to say "that dictation was lost" without
    /// interrupting whatever the user is doing (details are in the log).
    private func flashErrorIcon() {
        statusItem.button?.image = errorIcon
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.statusItem.button?.image = self.idleIcon
        }
    }

    // MARK: - Config actions

    @objc private func openSettings() {
        settings.show(config: config) { [weak self] updated in
            guard let self else { return }
            do {
                try updated.save()
                self.config = updated
            } catch {
                NSLog("[Susurro] failed to save config: \(error)")
            }
        }
    }

}

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addItem(action title: String, _ selector: Selector, target: AnyObject?, key: String) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        addItem(item)
    }
}
