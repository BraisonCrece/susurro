import AppKit
import AVFoundation
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }

    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private let overlay = RecordingOverlay()
    private let settings = SettingsWindowController()
    private var config = Config.load()

    private lazy var idleIcon = Self.barsImage(color: .black, template: true)
    private lazy var recordingIcon = Self.barsImage(color: .systemRed, template: false)

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
        requestPermissions()

        recorder.onLevel = { [weak self] level in self?.overlay.update(level: level) }
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndProcess() }
        hotkey.start()

        if !config.hasKey { showMissingKeyAlert() }
    }

    /// Reopening the app (from Raycast, Spotlight or the Dock) has no main window to restore,
    /// so we surface the settings window instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = idleIcon

        let menu = NSMenu()
        menu.addItem(disabled: "Susurro")
        menu.addItem(.separator())
        menu.addItem(disabled: "Mantén ⌥ (Option derecho) para dictar")
        menu.addItem(.separator())
        menu.addItem(action: "Configuración…", #selector(openSettings), target: self, key: ",")
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

    // MARK: - Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
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
        guard let fileURL = recorder.stop() else {
            state = .idle
            return
        }
        state = .processing
        let cfg = config

        Task {
            defer { try? FileManager.default.removeItem(at: fileURL) }
            do {
                let client = GroqClient(config: cfg)
                let raw = try await client.transcribe(fileURL: fileURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    let clean = try await client.cleanup(transcript: raw)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run { TextInjector.inject(clean) }
                }
            } catch {
                NSLog("[Susurro] pipeline failed: \(error.localizedDescription)")
            }
            await MainActor.run { self.state = .idle }
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
                NSLog("[Susurro] no se pudo guardar la configuración: \(error)")
            }
        }
    }

    private func showMissingKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Falta la API key de Groq"
        alert.informativeText = "Abre la configuración y pega tu clave de Groq para empezar a dictar."
        alert.addButton(withTitle: "Abrir configuración")
        alert.addButton(withTitle: "Más tarde")
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
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
