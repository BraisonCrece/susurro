import Foundation

struct Config {
    static let defaultTranscriptionModel = "whisper-large-v3-turbo"
    static let defaultCleanupModel = "llama-3.3-70b-versatile"
    private static let placeholderKey = "gsk_REPLACE_ME"

    var groqApiKey: String
    var transcriptionModel: String
    var cleanupModel: String
    var language: String?
    var systemPrompt: String
    /// Read the text before the caret (via Accessibility) and send it to the refiner so
    /// burst dictations continue the sentence naturally. Off ⇒ nothing but the audio ever
    /// leaves the machine.
    var useCursorContext: Bool
    /// Terms Whisper tends to misspell (product names, jargon). They bias the transcription
    /// and the refiner enforces their exact spelling.
    var dictionary: [String]

    var hasKey: Bool {
        !groqApiKey.isEmpty && groqApiKey != Self.placeholderKey
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
    - Convert punctuation dictated by name in the speaker's language into the mark itself \
    ("coma" → ",", "punto" → ".", "dos puntos" → ":", "punto y aparte" → paragraph break, \
    "entre comillas …" → quoted text; "comma", "period", "question mark", "new line", …), \
    only when the wording makes clear it is dictated punctuation and not content.
    - When the speaker dictates an enumeration with spoken numbers or ordinals ("uno, \
    manzanas, dos, plátanos", "1. apples 2. bananas", "primero…, segundo…"), format it as a \
    list: one item per line, numbered ("1. ", "2. ") if numbers were spoken, dashed otherwise. \
    Words spoken before the enumeration are kept verbatim as an introductory line ending \
    with ":" — never dropped.
    - When the speaker names a casing convention for an identifier (camel case, snake case, \
    kebab case, all caps / en mayúsculas), apply the convention to that identifier and drop \
    the convention words — they are instructions, not content. Example: "La variable user id \
    en camel case" becomes "La variable userId"; "max retries en snake case en mayúsculas" \
    becomes "MAX_RETRIES". Keep well-known acronyms uppercase (API, URL, JSON, SQL).

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

    // MARK: - Persistence

    /// On-disk shape. Every field is optional so a hand-edited file can omit anything, and
    /// defaults are never frozen into the file — prompt or model improvements shipped in
    /// later builds reach existing installs.
    private struct Stored: Codable {
        var groqApiKey: String?
        var transcriptionModel: String?
        var cleanupModel: String?
        var language: String?
        var systemPrompt: String?
        var useCursorContext: Bool?
        var dictionary: [String]?
    }

    func save() throws {
        let stored = Stored(
            groqApiKey: groqApiKey,
            transcriptionModel: transcriptionModel,
            cleanupModel: cleanupModel,
            language: language.flatMap { $0.isEmpty ? nil : $0 },
            systemPrompt: systemPrompt == Self.defaultSystemPrompt ? nil : systemPrompt,
            useCursorContext: useCursorContext ? nil : false,
            dictionary: dictionary.isEmpty ? nil : dictionary
        )
        try FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        try Self.encoder.encode(stored).write(to: Self.configURL)
    }

    static func load() -> Config {
        let stored = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
            ?? Stored()
        return Config(
            groqApiKey: stored.groqApiKey ?? ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? "",
            transcriptionModel: stored.transcriptionModel ?? defaultTranscriptionModel,
            cleanupModel: stored.cleanupModel ?? defaultCleanupModel,
            language: stored.language,
            systemPrompt: stored.systemPrompt ?? defaultSystemPrompt,
            useCursorContext: stored.useCursorContext ?? true,
            dictionary: stored.dictionary ?? []
        )
    }

    static func writeTemplateIfMissing() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let template = Stored(
            groqApiKey: placeholderKey,
            transcriptionModel: defaultTranscriptionModel,
            cleanupModel: defaultCleanupModel,
            language: "es",
            systemPrompt: nil
        )
        try? encoder.encode(template).write(to: configURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static var configDir: URL {
        // Honor $HOME like any tool that keeps dotfiles under ~/.config (the Foundation
        // home-directory APIs ignore it and always use the account's home). This also lets
        // tests point the config at a scratch directory.
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config/susurro", isDirectory: true)
    }

    static var configURL: URL {
        configDir.appendingPathComponent("config.json")
    }
}
