import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

/// The app is normally an accessory (menu-bar only). Windows that need keyboard focus flip
/// it to a regular activation policy while open; a refcount keeps simultaneous windows
/// (settings + onboarding) from fighting over the policy.
enum AppActivation {
    private static var openWindows = 0

    static func windowDidOpen() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowDidClose() {
        openWindows -= 1
        if openWindows <= 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

/// First-run checklist: the two TCC permissions plus the Groq key, with live status so each
/// step turns green the moment it is granted. macOS offers no API to grant Microphone or
/// Accessibility programmatically — the closest any app can get is deep-linking into the
/// exact System Settings pane and detecting the grant as it happens.
struct OnboardingView: View {
    let saveKey: (String) -> Void
    let close: () -> Void

    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var apiKey = ""
    @State private var keySaved: Bool

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(hasKey: Bool, saveKey: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.saveKey = saveKey
        self.close = close
        _keySaved = State(initialValue: hasKey)
    }

    private var allDone: Bool { micStatus == .authorized && axTrusted && keySaved }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configura Susurro")
                .font(.title2.bold())
            Text("Tres pasos y a dictar en cualquier app.")
                .foregroundColor(.secondary)

            step(title: "Micrófono",
                 detail: "Para grabar tu voz mientras dictas.",
                 done: micStatus == .authorized) {
                Button(micStatus == .notDetermined ? "Permitir…" : "Abrir Ajustes…",
                       action: requestMicrophone)
            }

            step(title: "Accesibilidad",
                 detail: "Para detectar ⌥ y pegar el texto. Enciende el interruptor de Susurro en la lista.",
                 done: axTrusted) {
                Button("Abrir Ajustes…", action: requestAccessibility)
            }

            step(title: "API key de Groq",
                 detail: keySaved ? "Guardada." : "Gratis en console.groq.com/keys.",
                 done: keySaved) {
                EmptyView()
            }
            if !keySaved {
                HStack(spacing: 6) {
                    SecureField("gsk_…", text: $apiKey)
                    Button("Guardar") {
                        saveKey(trimmedKey)
                        keySaved = true
                    }
                    .disabled(trimmedKey.isEmpty)
                }
                .padding(.leading, 34)
            }

            Divider()

            HStack {
                if allDone {
                    Text("Todo listo: mantén ⌥ (Option derecho) y habla.")
                        .font(.callout.weight(.medium))
                } else {
                    Link("Conseguir una API key", destination: URL(string: "https://console.groq.com/keys")!)
                        .font(.caption)
                }
                Spacer()
                Button(allDone ? "Empezar a dictar" : "Más tarde", action: close)
                    .keyboardShortcut(allDone ? .defaultAction : .cancelAction)
            }
        }
        .padding(22)
        .frame(width: 500)
        .onReceive(refresh) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            axTrusted = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private func step(title: String, detail: String, done: Bool,
                      @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundColor(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !done { control() }
        }
    }

    private func requestMicrophone() {
        if micStatus == .notDetermined {
            // First time macOS shows its native Allow/Deny dialog — this one IS one click.
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else {
            openSettingsPane("Privacy_Microphone")
        }
    }

    private func requestAccessibility() {
        // Registers Susurro in the Accessibility list (may also show Apple's own prompt),
        // then jumps straight to the pane so the user only has to flip the switch.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
        openSettingsPane("Privacy_Accessibility")
    }

    private func openSettingsPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(hasKey: Bool, saveKey: @escaping (String) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(hasKey: hasKey, saveKey: saveKey) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Bienvenido a Susurro"
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
