import AppKit

/// Push-to-talk via a held modifier key. Default: Right Option (⌥).
/// Modifiers are used on purpose so the trigger never types a character into the focused app,
/// which means no event suppression / event tap is required.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private let triggerKeyCode: UInt16 = 61          // Right Option (⌥)
    private let triggerFlag: NSEvent.ModifierFlags = .option
    private var isDown = false
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
        guard event.keyCode == triggerKeyCode else { return }
        let pressed = event.modifierFlags.contains(triggerFlag)
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }
}
