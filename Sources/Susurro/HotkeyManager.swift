import AppKit

/// Dictation gestures on the Option keys, hybrid push-to-talk / toggle:
/// - Hold Right ⌥ and release (≥0.4 s): classic push-to-talk.
/// - Tap Right ⌥ (<0.4 s, nothing else pressed meanwhile): latch the recording hands-free
///   until the next tap.
/// - Tap Left ⌥ while recording: cancel, nothing reaches the network.
/// Modifiers are used on purpose so no gesture ever types a character into the focused app,
/// which means no event suppression / event tap is required — everything rides passive
/// NSEvent monitors.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// The recording in progress must be discarded without transcribing: either the cancel
    /// key was tapped, or the "trigger" turned out to be a keyboard shortcut.
    var onCancel: (() -> Void)?

    private enum Phase {
        case idle
        /// Trigger physically held, recording. `dirty` flips when any other key or click
        /// arrives mid-hold: the gesture was a shortcut (⌥2 → "@"), not dictation.
        case holding(since: Date, dirty: Bool)
        /// A clean tap latched the recording on, hands-free, until the next tap.
        case latched
        /// The gesture already resolved (cancel, latched stop, external cap) but the
        /// trigger is still physically down; its release must not fire anything.
        case draining
    }

    /// Releases under this are a tap (→ latch), over it a push-to-talk (→ process).
    /// Nothing is lost at the boundary: the speech gate already discards recordings
    /// shorter than 0.4 s, so a sub-threshold hold never produced text anyway.
    private let tapThreshold: TimeInterval = 0.4
    private let triggerKeyCode: UInt16 = 61          // Right Option (⌥)
    private let cancelKeyCode: UInt16 = 58           // Left Option (⌥)
    // The generic .option flag stays set while EITHER Option key is down, which would make
    // a trigger release invisible when the other Option is also held. The per-side device
    // bits (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK, stable since NeXT) disambiguate.
    private static let rightOptionMask: UInt = 0x40
    private static let leftOptionMask: UInt = 0x20

    private var phase = Phase.idle
    private var cancelDown = false
    private var monitors: [Any] = []

    func start() {
        let taps: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlags(event)
            },
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlags(event)
                return event
            },
            NSEvent.addGlobalMonitorForEvents(matching: taps) { [weak self] _ in
                self?.markDirty()
            },
            NSEvent.addLocalMonitorForEvents(matching: taps) { [weak self] event in
                self?.markDirty()
                return event
            },
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The recording ended outside the gesture (the safety cap in AppDelegate): resolve
    /// the phase so the next press starts fresh instead of acting on stale state.
    func endGesture() {
        switch phase {
        case .latched: phase = .idle
        case .holding: phase = .draining
        case .idle, .draining: break
        }
    }

    private func handleFlags(_ event: NSEvent) {
        switch event.keyCode {
        case triggerKeyCode:
            handleTrigger(pressed: event.modifierFlags.rawValue & Self.rightOptionMask != 0)
        case cancelKeyCode:
            handleCancel(pressed: event.modifierFlags.rawValue & Self.leftOptionMask != 0)
        default:
            break
        }
    }

    private func handleTrigger(pressed: Bool) {
        switch (phase, pressed) {
        case (.idle, true):
            phase = .holding(since: Date(), dirty: false)
            onPress?()
        case (.latched, true):
            // The tap that closes a latched dictation, resolved on key-down for
            // immediacy; its release is drained.
            phase = .draining
            onRelease?()
        case let (.holding(since, dirty), false):
            if dirty {
                phase = .idle
                onCancel?()
            } else if Date().timeIntervalSince(since) < tapThreshold {
                phase = .latched
            } else {
                phase = .idle
                onRelease?()
            }
        case (.draining, false):
            phase = .idle
        case (.idle, false), (.latched, false), (.holding, true), (.draining, true):
            break
        }
    }

    private func handleCancel(pressed: Bool) {
        let wasDown = cancelDown
        cancelDown = pressed
        // Only the down transition cancels, and only mid-recording; a Left Option typed
        // on its own (symbols, shortcuts) stays none of our business.
        guard pressed, !wasDown else { return }
        switch phase {
        case .holding:
            phase = .draining
            onCancel?()
        case .latched:
            phase = .idle
            onCancel?()
        case .idle, .draining:
            break
        }
    }

    private func markDirty() {
        guard case let .holding(since, false) = phase else { return }
        phase = .holding(since: since, dirty: true)
    }
}
