import AppKit
import SwiftUI

struct SettingsView: View {
    private let initial: Config
    private let onSave: (Config) -> Void
    private let onCancel: () -> Void

    @State private var apiKey: String
    @State private var language: String
    @State private var transcriptionModel: String
    @State private var cleanupModel: String
    @State private var useCursorContext: Bool

    init(initial: Config, onSave: @escaping (Config) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        _apiKey = State(initialValue: initial.hasKey ? initial.groqApiKey : "")
        _language = State(initialValue: initial.language ?? "")
        _transcriptionModel = State(initialValue: initial.transcriptionModel)
        _cleanupModel = State(initialValue: initial.cleanupModel)
        _useCursorContext = State(initialValue: initial.useCursorContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configuración de Susurro")
                .font(.headline)

            Form {
                SecureField("API key de Groq", text: $apiKey)
                Picker("Idioma", selection: $language) {
                    Text("Detección automática").tag("")
                    Text("Español").tag("es")
                    Text("English").tag("en")
                }
                TextField("Modelo de transcripción", text: $transcriptionModel)
                TextField("Modelo de refinado", text: $cleanupModel)
                Toggle("Leer el texto junto al cursor para continuar frases", isOn: $useCursorContext)
            }

            HStack {
                Link("Conseguir una API key", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Pasted keys often drag a trailing newline along; whitespace in the Authorization
    /// header makes every Groq request fail.
    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        var config = initial
        config.groqApiKey = trimmedKey
        config.language = language.isEmpty ? nil : language
        config.transcriptionModel = transcriptionModel
        config.cleanupModel = cleanupModel
        config.useCursorContext = useCursorContext
        onSave(config)
    }
}

/// Hosts the SwiftUI settings form in a regular window; AppActivation flips the app out of
/// accessory mode while it is open so the fields can take keyboard focus.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(config: Config, onSave: @escaping (Config) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            initial: config,
            onSave: { [weak self] updated in onSave(updated); self?.window?.close() },
            onCancel: { [weak self] in self?.window?.close() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Configuración de Susurro"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        AppActivation.windowDidOpen()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        AppActivation.windowDidClose()
    }
}
