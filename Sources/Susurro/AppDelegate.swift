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
    /// The last text a dictation delivered, in memory only (nothing persists): the safety
    /// net for "pasted over it" / "the app ate the paste".
    private var lastDictation: String?

    /// Single source of truth for the dictation pipeline. Driving the menu-bar icon and the
    /// overlay from here keeps them in sync, and makes stray hotkey events (like a tap while
    /// a previous dictation is still processing) harmless no-ops.
    private var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            statusItem.button?.image = state == .recording ? recordingIcon : idleIcon
            switch state {
            case .idle:
                overlay.hide()
                // Whatever ended (dictation, cancel), leave the engine prepared so the
                // next press starts capturing with less cold-start loss.
                prewarmRecorder()
            case .recording: overlay.showRecording()
            case .processing: overlay.showProcessing()
            }
        }
    }

    /// Prepared ≠ recording: no hardware starts and the mic indicator stays off. Skipped
    /// until the microphone grant exists so the first TCC prompt happens on a real
    /// dictation, not on app launch.
    private func prewarmRecorder() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        recorder.prewarm()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.writeTemplateIfMissing()
        setupStatusItem()

        recorder.onLevel = { [weak self] level in self?.overlay.update(level: level) }
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndProcess() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()
        prewarmRecorder()

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
        menu.addItem(disabled: "Mantén ⌥ derecho para dictar; un tap lo deja abierto")
        menu.addItem(disabled: "⌥ izquierdo cancela el dictado en curso")
        lastErrorItem.isEnabled = false
        lastErrorItem.isHidden = true
        menu.addItem(lastErrorItem)
        menu.addItem(.separator())
        menu.addItem(action: "Copiar último dictado", #selector(copyLastDictation),
                     target: self, key: "")
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

    /// No recording runs unbounded: a latched dictation the user forgot (or a wedged key)
    /// would keep the mic hot and grow past what Groq accepts (~25 MB ≈ 13 min of 16 kHz
    /// WAV). Five minutes of single-breath dictation is beyond any real use.
    private static let maxRecordingDuration: TimeInterval = 300
    private var recordingCap: Timer?

    private func startRecording() {
        guard state == .idle else { return }
        do {
            try recorder.start()
            state = .recording
            recordingCap = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingDuration,
                                                repeats: false) { [weak self] _ in
                guard let self, self.state == .recording else { return }
                self.hotkey.endGesture()
                self.stopAndProcess()
            }
        } catch {
            NSLog("[Susurro] record start failed: \(error)")
        }
    }

    /// The user regretted the dictation mid-recording (or it was a shortcut all along):
    /// throw the audio away, nothing reaches the network.
    private func cancelRecording() {
        guard state == .recording else { return }
        recordingCap?.invalidate()
        recorder.stop()?.removeFile()
        state = .idle
    }

    private func stopAndProcess() {
        guard state == .recording else { return }
        recordingCap?.invalidate()
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
        case .injected(let text):
            lastDictation = text
        case .empty:
            break
        case .injectedRaw(let text, let error):
            // The words landed (raw), so no alarming flash: the menu explains why the
            // text arrived unpolished, for when the user goes looking.
            lastDictation = text
            showLastError("Refinado caído, se pegó la transcripción tal cual — \(Self.describe(error))")
        case .clipboardOnly(let text):
            // The text survives on the clipboard; the checklist window shows exactly
            // which permission died and fixes it in one click.
            lastDictation = text
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

    /// A deliberate copy the user asked for: a plain write, free to live in clipboard
    /// managers, never auto-restored away.
    @objc private func copyLastDictation() {
        guard let lastDictation else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastDictation, forType: .string)
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

extension AppDelegate: NSMenuItemValidation {
    /// "Copiar último dictado" stays grayed out until a dictation has delivered text.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyLastDictation) { return lastDictation != nil }
        return true
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
