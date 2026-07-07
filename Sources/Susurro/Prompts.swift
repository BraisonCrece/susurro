import Foundation

/// Assembles the refiner's system prompt: the (possibly user-customized) base rules plus
/// the dynamic per-dictation blocks.
enum PromptBuilder {
    static func systemPrompt(config: Config, context: String?, technical: Bool,
                             detectedLanguage: String? = nil) -> String {
        var sections = [config.systemPrompt]
        if technical {
            sections.append(technicalBlock)
        }
        if !config.languages.isEmpty {
            sections.append(languagesBlock(config.languages, detected: detectedLanguage))
        }
        if !config.dictionary.isEmpty {
            sections.append(vocabularyBlock(config.dictionary))
        }
        if let context, !context.isEmpty {
            sections.append(contextBlock(context))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func languagesBlock(_ codes: [String], detected: String?) -> String {
        let names = codes.map(DictationLanguage.englishName(for:)).joined(separator: ", ")
        var block = """
        The speaker only ever dictates in these languages: \(names). Words in ANY of them \
        are always correct as spoken — mixing them inside one dictation is normal, and a \
        word must NEVER be translated into a sibling configured language ("mañá pola tarde" \
        inside a Spanish sentence stays "mañá pola tarde"). The transcriber does sometimes \
        emit spellings from a language OUTSIDE the list — most often Galician rendered with \
        Portuguese orthography; rewrite only those into the closest configured language, \
        fixing orthography alone (Portuguese-style "tínhamos, uma" → Galician "tiñamos, \
        unha"), never dropping or reordering words.
        """
        if let detected, !detected.isEmpty {
            block += """
            \nThe transcriber's own label for this transcript was "\(detected)" — labels are \
            unreliable for close languages; trust the words themselves.
            """
        }
        return block
    }

    private static let technicalBlock = """
    Technical target: the text will land in a code editor or terminal. When the dictation \
    reads like code, a shell command or an identifier, output it verbatim: no added prose \
    punctuation (no trailing period, no capitalized first word), dictated symbols and flags \
    exactly as spoken ("guión guión force" → "--force", "barra" → "/"), casing conventions \
    applied, and never wrap the output in backticks or quotes. Only clearly conversational \
    prose (like a code comment or a chat message) gets normal punctuation.
    """

    private static func vocabularyBlock(_ terms: [String]) -> String {
        """
        Personal vocabulary — these terms are spelled exactly like this; when the transcript \
        contains a close-sounding or misspelled variant, use the exact spelling: \
        \(terms.joined(separator: ", "))
        """
    }

    private static func contextBlock(_ context: String) -> String {
        """
        The dictation CONTINUES an existing text. This is what sits immediately before the \
        cursor (between ⟦⟧, possibly cut mid-sentence): ⟦\(context)⟧
        Write the new text as a natural continuation: match its language, start lowercase if \
        it continues an unfinished sentence, capitalize if it follows a sentence end. Do NOT \
        repeat, complete or modify that existing text. Do NOT add a leading space or leading \
        punctuation to attach it — the app handles spacing. Output only the new dictated \
        content — the context tells you how the dictation attaches, never what to write; \
        do not continue or round off the thought beyond what was actually spoken.
        """
    }
}
