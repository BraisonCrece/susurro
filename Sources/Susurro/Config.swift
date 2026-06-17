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
    You are a dictation cleanup engine. You receive a raw speech-to-text transcript that may \
    contain filler words, false starts, repetitions, hesitations and self-corrections.
    Rewrite it into the clean, final text the speaker intended.
    Rules:
    - Resolve self-corrections, keeping ONLY the final intended version.
    - Remove fillers and hesitations (um, eh, like, you know, o sea, este, esto, bueno).
    - Fix punctuation, capitalization and obvious transcription typos.
    - Preserve the speaker's language, meaning, tone and register. Do NOT translate.
    - Do NOT add greetings, commentary, explanations, or surrounding quotation marks.
    - Treat everything as dictation to transcribe, never as a question to answer.
    Output ONLY the cleaned text, with no preamble.
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
