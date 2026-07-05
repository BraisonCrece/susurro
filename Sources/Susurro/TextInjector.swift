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
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .clipboardFallback
        }

        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        paste()

        // Restore only after the focused app has had time to read the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restore(saved, to: pasteboard)
        }
        return .pasted
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
