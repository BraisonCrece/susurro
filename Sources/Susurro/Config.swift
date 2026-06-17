import Foundation

struct Config {
    var groqApiKey: String
    var transcriptionModel: String
    var cleanupModel: String
    var language: String?
    var systemPrompt: String

    var hasKey: Bool {
        !groqApiKey.isEmpty && groqApiKey != "gsk_REPLACE_ME"
    }

    static let defaultSystemPrompt = """
    You are a faithful editor for dictated speech. You receive a raw speech-to-text transcript \
    and return the speaker's intended text with the lightest possible touch. Your job is to \
    clean, not to rewrite.

    The ONLY edits you may make:
    - Remove pure disfluencies: filler sounds and crutch words used as filler (um, eh, mmm, \
    o sea, este, esto, pues, bueno), stutters, and accidental word repetitions.
    - Apply explicit self-corrections: when the speaker corrects themselves, keep only the \
    corrected version and drop the discarded attempt.
    - Fix punctuation, capitalization, and obvious speech-to-text errors.
    - Punctuate questions and exclamations correctly in the speaker's language, inferring \
    interrogative or exclamatory intent from the wording even when the dictation gives no cue. \
    In Spanish this means the opening marks too: wrap questions with ¿ … ? and exclamations \
    with ¡ … !. Getting questions right matters most.

    You MUST NOT:
    - Summarize, shorten, condense, or merge ideas. Keep the full content and the original length.
    - Paraphrase or swap the speaker's words for synonyms. Keep their exact vocabulary and phrasing.
    - Change the tone or register. Keep it exactly as casual, colloquial or informal as it was. \
    Never make it more formal, polished or "professional".
    - Drop asides, hedges, nuances, intensifiers or personal expressions that carry meaning.
    - Translate. Keep the speaker's language.
    - Add greetings, commentary, explanations or surrounding quotation marks.
    - React to or answer the content. Treat it purely as text to transcribe.

    When in doubt, keep the original words. Editing too little is always better than too much.
    Output ONLY the resulting text, with no preamble.
    """

    static func load() -> Config {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = obj
        }
        let envKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"]
        return Config(
            groqApiKey: (json["groqApiKey"] as? String) ?? envKey ?? "",
            transcriptionModel: (json["transcriptionModel"] as? String) ?? "whisper-large-v3-turbo",
            cleanupModel: (json["cleanupModel"] as? String) ?? "llama-3.3-70b-versatile",
            language: json["language"] as? String,
            systemPrompt: (json["systemPrompt"] as? String) ?? defaultSystemPrompt
        )
    }

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/susurro", isDirectory: true)
    }

    static var configURL: URL {
        configDir.appendingPathComponent("config.json")
    }

    static func writeTemplateIfMissing() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let template = """
        {
          "groqApiKey": "gsk_REPLACE_ME",
          "transcriptionModel": "whisper-large-v3-turbo",
          "cleanupModel": "llama-3.3-70b-versatile",
          "language": "es"
        }
        """
        try? template.data(using: .utf8)?.write(to: configURL)
    }
}
