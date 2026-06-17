import AppKit
import AVFoundation
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }

    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private let overlay = RecordingOverlay()
    private var config = Config.load()
    private var isProcessing = false

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

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(.idle)

        let menu = NSMenu()
        menu.addItem(disabled: "Susurro")
        menu.addItem(.separator())
        menu.addItem(disabled: "Mantén ⌥ (Option derecho) para dictar")
        menu.addItem(.separator())
        menu.addItem(action: "Abrir configuración…", #selector(openConfig), target: self, key: ",")
        menu.addItem(action: "Recargar configuración", #selector(reloadConfig), target: self, key: "r")
        menu.addItem(.separator())
        menu.addItem(action: "Salir", #selector(NSApplication.terminate(_:)), target: nil, key: "q")
        statusItem.menu = menu
    }

    private func setIcon(_ state: State) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case .idle: symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .processing: symbol = "ellipsis"
        }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Susurro") {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "S"
        }
    }

    // MARK: - Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Recording pipeline

    private func startRecording() {
        guard !isProcessing else { return }
        do {
            try recorder.start()
            setIcon(.recording)
            overlay.showRecording()
        } catch {
            NSLog("[Susurro] record start failed: \(error)")
        }
    }

    private func stopAndProcess() {
        guard let fileURL = recorder.stop() else {
            setIcon(.idle)
            overlay.hide()
            return
        }
        isProcessing = true
        setIcon(.processing)
        overlay.showProcessing()
        let cfg = config

        Task {
            defer { try? FileManager.default.removeItem(at: fileURL) }
            do {
                let client = GroqClient(config: cfg)
                let raw = try await client.transcribe(fileURL: fileURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { await self.finish(); return }

                let clean = try await client.cleanup(transcript: raw)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { TextInjector.inject(clean) }
            } catch {
                NSLog("[Susurro] pipeline failed: \(error.localizedDescription)")
            }
            await self.finish()
        }
    }

    @MainActor
    private func finish() {
        isProcessing = false
        setIcon(.idle)
        overlay.hide()
    }

    // MARK: - Config actions

    @objc private func openConfig() {
        Config.writeTemplateIfMissing()
        NSWorkspace.shared.open(Config.configURL)
    }

    @objc private func reloadConfig() {
        config = Config.load()
        if !config.hasKey { showMissingKeyAlert() }
    }

    private func showMissingKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Falta la API key de Groq"
        alert.informativeText = """
        Añade tu clave de Groq en:
        \(Config.configURL.path)

        Después usa “Recargar configuración” en el menú.
        """
        alert.addButton(withTitle: "Abrir configuración")
        alert.addButton(withTitle: "Más tarde")
        if alert.runModal() == .alertFirstButtonReturn { openConfig() }
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
