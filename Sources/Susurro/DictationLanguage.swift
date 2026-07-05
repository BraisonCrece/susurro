import Foundation

/// Languages offered in settings. The UI shows the native name; prompts (and Whisper's
/// verbose_json `language` field) speak English names.
struct DictationLanguage: Identifiable {
    let code: String
    let name: String
    let englishName: String

    var id: String { code }

    static let catalog: [DictationLanguage] = [
        DictationLanguage(code: "es", name: "Español", englishName: "Spanish"),
        DictationLanguage(code: "gl", name: "Galego", englishName: "Galician"),
        DictationLanguage(code: "en", name: "English", englishName: "English"),
        DictationLanguage(code: "pt", name: "Português", englishName: "Portuguese"),
        DictationLanguage(code: "ca", name: "Català", englishName: "Catalan"),
        DictationLanguage(code: "fr", name: "Français", englishName: "French"),
        DictationLanguage(code: "de", name: "Deutsch", englishName: "German"),
        DictationLanguage(code: "it", name: "Italiano", englishName: "Italian"),
    ]

    static func name(for code: String) -> String {
        catalog.first { $0.code == code }?.name ?? code
    }

    static func englishName(for code: String) -> String {
        catalog.first { $0.code == code }?.englishName ?? code
    }
}
