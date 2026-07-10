import AppKit

/// Result of the cloud half of a dictation, for the UI layer to present.
enum DictationOutcome {
    /// Text landed in the focused app.
    case injected
    /// The refiner failed, so the raw transcript landed instead — unpolished beats lost.
    case injectedRaw(Error)
    /// Nothing worth pasting came back.
    case empty
    /// Text was ready but the synthetic ⌘V was impossible (Accessibility grant missing or
    /// silently invalidated by TCC); it was left on the clipboard instead.
    case clipboardOnly
    /// Transcription failed: there is nothing to deliver.
    case failed(Error)
}

/// Runs one recording through transcribe → refine → inject. UI-free: it reports a
/// DictationOutcome and the caller decides how to present it.
struct DictationPipeline {
    let config: Config

    /// The refiner rewrote a non-empty transcript into nothing — it ate the dictation.
    struct EmptyRefinement: LocalizedError {
        var errorDescription: String? { "el refinador devolvió una respuesta vacía" }
    }

    func run(recording: Recording, context: String?, technical: Bool) async -> DictationOutcome {
        defer { recording.removeFile() }
        let client = GroqClient(config: config)
        let transcription: GroqClient.Transcription
        do {
            transcription = try await client.transcribe(fileURL: recording.fileURL)
        } catch {
            return .failed(error)
        }
        // Known mishearings get fixed deterministically before anything else looks at the
        // transcript: the refiner sees the right spelling, and so does the raw fallback.
        let raw = Corrections.apply(config.corrections,
                                    to: transcription.text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !raw.isEmpty else { return .empty }

        // Refinement is an enhancement, never a gate: once Whisper heard the words, text
        // WILL land. If the refiner errors out or eats the transcript, the raw transcript
        // is delivered as-is — the words are the user's, the polish is optional.
        do {
            let clean = try await cleanupWithFallback(client: client, raw: raw, context: context,
                                                      technical: technical,
                                                      detectedLanguage: transcription.language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw EmptyRefinement() }
            return await deliver(clean, after: context, refinerFailure: nil)
        } catch {
            NSLog("[Susurro] refiner failed, delivering raw transcript: %@",
                  error.localizedDescription)
            return await deliver(raw, after: context, refinerFailure: error)
        }
    }

    private func deliver(_ text: String, after context: String?,
                         refinerFailure: Error?) async -> DictationOutcome {
        let text = Self.applyingLeadingSpace(to: text, after: context)
        return await MainActor.run {
            switch TextInjector.inject(text) {
            case .pasted:
                return refinerFailure.map(DictationOutcome.injectedRaw) ?? .injected
            case .clipboardFallback:
                return .clipboardOnly
            }
        }
    }

    /// Groq rate-limits per model, so when the configured model runs out of daily tokens
    /// (HTTP 429) the dictation still lands via the fallback model's own budget.
    private func cleanupWithFallback(client: GroqClient, raw: String, context: String?,
                                     technical: Bool, detectedLanguage: String?) async throws -> String {
        do {
            return try await client.cleanup(transcript: raw, model: config.cleanupModel,
                                            context: context, technical: technical,
                                            detectedLanguage: detectedLanguage)
        } catch GroqClient.ClientError.http(429, _)
            where config.cleanupModel != Config.fallbackCleanupModel {
            NSLog("[Susurro] %@ rate-limited, retrying with %@",
                  config.cleanupModel, Config.fallbackCleanupModel)
            return try await client.cleanup(transcript: raw, model: Config.fallbackCleanupModel,
                                            context: context, technical: technical,
                                            detectedLanguage: detectedLanguage)
        }
    }

    /// A leading space is added only when the character before the caret could actually be
    /// read and requires one ("…jueves." + "Además…"). With no readable context the text is
    /// pasted verbatim: a wrongly added space at a line start is worse than a missing one
    /// after a period.
    static func applyingLeadingSpace(to text: String, after context: String?) -> String {
        guard let previous = context?.last, let first = text.first else { return text }
        guard !previous.isWhitespace else { return text }
        let noSpaceAfter: Set<Character> = ["(", "[", "{", "¿", "¡", "\"", "'", "«", "/", "@", "#", "-", "_"]
        guard !noSpaceAfter.contains(previous) else { return text }
        guard first.isLetter || first.isNumber || first == "¿" || first == "¡" else { return text }
        return " " + text
    }
}
