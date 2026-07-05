import AppKit
import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable { case general, dictionary, advanced }

    private let initial: Config
    private let onSave: (Config) -> Void
    private let onCancel: () -> Void

    @State private var tab: Tab
    @State private var apiKey: String
    @State private var language: String
    @State private var transcriptionModel: String
    @State private var cleanupModel: String
    @State private var useCursorContext: Bool
    @State private var dictionary: [String]
    @State private var newTerm = ""
    @State private var selectedTerm: String?

    init(initial: Config,
         initialTab: Tab = .general,
         onSave: @escaping (Config) -> Void,
         onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        _tab = State(initialValue: initialTab)
        _apiKey = State(initialValue: initial.hasKey ? initial.groqApiKey : "")
        _language = State(initialValue: initial.language ?? "")
        _transcriptionModel = State(initialValue: initial.transcriptionModel)
        _cleanupModel = State(initialValue: initial.cleanupModel)
        _useCursorContext = State(initialValue: initial.useCursorContext)
        _dictionary = State(initialValue: initial.dictionary)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(Tab.general)
                dictionaryTab
                    .tabItem { Label("Diccionario", systemImage: "character.book.closed") }
                    .tag(Tab.dictionary)
                advancedTab
                    .tabItem { Label("Avanzado", systemImage: "slider.horizontal.3") }
                    .tag(Tab.advanced)
            }
            .padding([.top, .horizontal], 12)

            Divider()

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
            .padding(14)
        }
        .frame(width: 540, height: 440)
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section {
                SecureField("API key de Groq", text: $apiKey)
            }
            Section {
                Picker("Idioma del dictado", selection: $language) {
                    Text("Detección automática").tag("")
                    Text("Español").tag("es")
                    Text("Galego").tag("gl")
                    Text("English").tag("en")
                }
                Toggle("Contexto del cursor", isOn: $useCursorContext)
            } footer: {
                Text("Con el contexto activo, Susurro lee el texto junto al cursor para continuar frases con el espaciado y las mayúsculas correctos.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dictionaryTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Términos que Susurro suele escribir mal: nombres propios, marcas, jerga. Se transcriben y se corrigen siempre con esta grafía exacta.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selectedTerm) {
                ForEach(dictionary, id: \.self) { term in
                    Text(term).tag(term)
                }
            }
            .listStyle(.bordered)

            HStack(spacing: 8) {
                TextField("Nuevo término (p. ej. Claude)", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button(action: addTerm) { Image(systemName: "plus") }
                    .disabled(trimmedNewTerm.isEmpty)
                    .help("Añadir término")
                Button(action: removeSelectedTerm) { Image(systemName: "minus") }
                    .disabled(selectedTerm == nil)
                    .help("Eliminar el término seleccionado")
            }
        }
        .padding(16)
    }

    private var advancedTab: some View {
        Form {
            Section {
                TextField("Transcripción", text: $transcriptionModel)
                TextField("Refinado", text: $cleanupModel)
            } header: {
                Text("Modelos de Groq")
            } footer: {
                Text("El modelo de transcripción convierte tu voz en texto y el de refinado lo limpia. Déjalos como están salvo que sepas lo que buscas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    /// Pasted keys often drag a trailing newline along; whitespace in the Authorization
    /// header makes every Groq request fail.
    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewTerm: String {
        newTerm.trimmingCharacters(in: .whitespaces)
    }

    private func addTerm() {
        let term = trimmedNewTerm
        newTerm = ""
        guard !term.isEmpty, !dictionary.contains(term) else { return }
        dictionary.append(term)
    }

    private func removeSelectedTerm() {
        guard let selectedTerm else { return }
        dictionary.removeAll { $0 == selectedTerm }
        self.selectedTerm = nil
    }

    private func save() {
        var config = initial
        config.groqApiKey = trimmedKey
        config.language = language.isEmpty ? nil : language
        config.transcriptionModel = transcriptionModel
        config.cleanupModel = cleanupModel
        config.useCursorContext = useCursorContext
        config.dictionary = dictionary
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
