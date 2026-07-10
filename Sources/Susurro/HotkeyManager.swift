import AppKit

/// Push-to-talk via a held modifier key. Default: Right Option (⌥) records, Left Option
/// (⌥) cancels the recording in progress.
/// Modifiers are used on purpose so neither gesture ever types a character into the focused
/// app, which means no event suppression / event tap is required — everything rides the
/// same passive flagsChanged stream.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// The cancel key was tapped while the trigger was held: discard the recording in
    /// progress without transcribing. After it fires, the trigger release is swallowed.
    var onCancel: (() -> Void)?

    private let triggerKeyCode: UInt16 = 61          // Right Option (⌥)
    private let cancelKeyCode: UInt16 = 58           // Left Option (⌥)
    // The generic .option flag stays set while EITHER Option key is down, which would make
    // a trigger release invisible when the other Option is also held. The per-side device
    // bits (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK, stable since NeXT) disambiguate.
    private static let rightOptionMask: UInt = 0x40
    private static let leftOptionMask: UInt = 0x20

    private var triggerDown = false
    private var cancelDown = false
    private var canceled = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case triggerKeyCode:
            let pressed = event.modifierFlags.rawValue & Self.rightOptionMask != 0
            if pressed && !triggerDown {
                triggerDown = true
                canceled = false
                onPress?()
            } else if !pressed && triggerDown {
                triggerDown = false
                if !canceled { onRelease?() }
            }
        case cancelKeyCode:
            let pressed = event.modifierFlags.rawValue & Self.leftOptionMask != 0
            let wasDown = cancelDown
            cancelDown = pressed
            // Only the down transition cancels, and only mid-recording; a Left Option
            // typed on its own (symbols, shortcuts) stays none of our business.
            guard pressed, !wasDown, triggerDown, !canceled else { return }
            canceled = true
            onCancel?()
        default:
            break
        }
    }
}
