import AppKit

/// Result of the cloud half of a dictation, for the UI layer to present.
enum DictationOutcome {
    /// Text landed in the focused app.
    case injected
    /// Nothing worth pasting came back.
    case empty
    /// Text was ready but the synthetic ⌘V was impossible (Accessibility grant missing or
    /// silently invalidated by TCC); it was left on the clipboard instead.
    case clipboardOnly
    /// Transcription or refinement failed.
    case failed(Error)
}

/// Runs one recording through transcribe → refine → inject. UI-free: it reports a
/// DictationOutcome and the caller decides how to present it.
struct DictationPipeline {
    let config: Config

    func run(recording: Recording, context: String?, technical: Bool) async -> DictationOutcome {
        defer { recording.removeFile() }
        do {
            let client = GroqClient(config: config)
            let raw = try await client.transcribe(fileURL: recording.fileURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return .empty }

            let clean = try await client.cleanup(transcript: raw, context: context, technical: technical)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return .empty }

            return await MainActor.run {
                switch TextInjector.inject(clean, after: context) {
                case .pasted: return DictationOutcome.injected
                case .clipboardFallback: return DictationOutcome.clipboardOnly
                }
            }
        } catch {
            return .failed(error)
        }
    }
}
