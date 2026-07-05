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
            let transcription = try await client.transcribe(fileURL: recording.fileURL)
            let raw = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return .empty }

            let clean = try await client.cleanup(transcript: raw, context: context, technical: technical,
                                                 detectedLanguage: transcription.language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return .empty }

            let text = Self.applyingLeadingSpace(to: clean, after: context)
            return await MainActor.run {
                switch TextInjector.inject(text) {
                case .pasted: return DictationOutcome.injected
                case .clipboardFallback: return DictationOutcome.clipboardOnly
                }
            }
        } catch {
            return .failed(error)
        }
    }

    /// A leading space is added only when the character before the caret could actually be
    /// read and requires one ("…jueves." + "Además…"). With no readable context the text is
    /// pasted verbatim: a wrongly added space at a line start is worse than a missing one
    /// after a period.
    private static func applyingLeadingSpace(to text: String, after context: String?) -> String {
        guard let previous = context?.last, let first = text.first else { return text }
        guard !previous.isWhitespace else { return text }
        let noSpaceAfter: Set<Character> = ["(", "[", "{", "¿", "¡", "\"", "'", "«", "/", "@", "#", "-", "_"]
        guard !noSpaceAfter.contains(previous) else { return text }
        guard first.isLetter || first.isNumber || first == "¿" || first == "¡" else { return text }
        return " " + text
    }
}
