import AppKit
import ApplicationServices
import CoreGraphics

/// Pastes text into whatever app has focus by briefly hijacking the clipboard:
/// snapshot the current contents, write our text, synthesize ⌘V, then restore the snapshot.
/// Pure mechanism: it pastes exactly what it is given — spacing policy lives upstream.
enum TextInjector {
    enum InjectionResult {
        case pasted
        /// The synthetic ⌘V was impossible (Accessibility grant missing, or silently
        /// invalidated by TCC); the text was left on the clipboard for a manual paste.
        case clipboardFallback
    }

    static func inject(_ text: String) -> InjectionResult {
        guard !text.isEmpty else { return .pasted }
        let pasteboard = NSPasteboard.general

        guard AXIsProcessTrusted() else {
            // A deliberate hand-off for a manual ⌘V — a regular (non-transient) write,
            // so clipboard managers may legitimately keep it.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .clipboardFallback
        }

        let saved = snapshot(pasteboard)
        writeTransient(text, to: pasteboard)
        let ourChange = pasteboard.changeCount
        paste()

        // Restore only after the focused app has had time to read the clipboard — and
        // only while it still holds our write: if the user copied something in the
        // meantime, their copy wins over the snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pasteboard.changeCount == ourChange else { return }
            restore(saved, to: pasteboard)
        }
        return .pasted
    }

    /// The dictation passes through the clipboard only to ride the synthetic ⌘V; the
    /// transient marker (the de-facto standard from nspasteboard.org) tells clipboard
    /// managers not to record it in their history.
    private static func writeTransient(_ text: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // "v"
        let location: CGEventTapLocation = .cgAnnotatedSessionEventTap

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: location)
        up?.post(tap: location)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
