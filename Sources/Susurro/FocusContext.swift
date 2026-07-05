import AppKit
import ApplicationServices

/// Reads the text immediately before the caret in the focused UI element, through the
/// Accessibility API (Susurro already holds the AX grant for the hotkey and ⌘V). It lets
/// the refiner continue an existing sentence naturally and the injector decide the leading
/// space exactly. Not every app exposes its text over AX (some Electron apps, web views) —
/// callers must treat nil as "unknown".
enum FocusContext {
    static func textBeforeCaret(maxLength: Int = 200) -> String? {
        var focusedRef: CFTypeRef?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let focused = focusedRef as! AXUIElement

        // Never read (nor ship to the cloud) password fields. Secure fields are regular
        // AXTextFields with the AXSecureTextField SUBrole, so that is the attribute to
        // check (macOS already refuses to expose their content, this is defense in depth).
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           subroleRef as? String == NSAccessibility.Subrole.secureTextField.rawValue {
            return nil
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString,
                                            &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }

        // A caret at position 0 is a real answer: there is nothing before the cursor.
        guard selection.location > 0 else { return "" }

        let start = max(0, selection.location - maxLength)
        var query = CFRange(location: start, length: selection.location - start)
        guard let queryValue = AXValueCreate(.cfRange, &query) else { return nil }

        var textRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                  focused, kAXStringForRangeParameterizedAttribute as CFString,
                  queryValue, &textRef) == .success,
              let text = textRef as? String
        else { return nil }
        return text
    }
}
