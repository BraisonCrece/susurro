import AppKit
import ApplicationServices
import CoreGraphics

/// Pastes text into whatever app has focus by briefly hijacking the clipboard:
/// snapshot the current contents, write our text, synthesize ⌘V, then restore the snapshot.
enum TextInjector {
    private struct LastInjection {
        let text: String
        let at: Date
        let appBundleId: String?
    }

    private static var last: LastInjection?

    static func inject(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general

        // Without the Accessibility grant the synthetic ⌘V never lands. Leave the text on
        // the clipboard (and skip the restore) so a manual paste can still recover it.
        guard AXIsProcessTrusted() else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let toPaste = heuristicNeedsLeadingSpace(before: text, in: frontApp) ? " " + text : text

        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(toPaste, forType: .string)
        paste()
        last = LastInjection(text: toPaste, at: Date(), appBundleId: frontApp)

        // Restore only after the focused app has had time to read the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - Leading space

    /// Dictating in bursts ("…el jueves." + ⌥ + "Además…") pastes flush against the
    /// previous sentence. Without reading the target field, all we know is our own last
    /// paste — trust it while it is fresh and the user stayed in the same app.
    private static func heuristicNeedsLeadingSpace(before text: String, in app: String?) -> Bool {
        guard let last,
              Date().timeIntervalSince(last.at) < 120,
              last.appBundleId == app,
              let previous = last.text.last,
              let first = text.first
        else { return false }
        return needsSpace(between: previous, and: first)
    }

    static func needsSpace(between previous: Character, and next: Character) -> Bool {
        guard !previous.isWhitespace else { return false }
        let noSpaceAfter: Set<Character> = ["(", "[", "{", "¿", "¡", "\"", "'", "«", "/", "@", "#", "-", "_"]
        guard !noSpaceAfter.contains(previous) else { return false }
        return next.isLetter || next.isNumber || next == "¿" || next == "¡"
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
