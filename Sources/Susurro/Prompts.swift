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
        The speaker dictates only in: \(names). Mixing them mid-dictation is normal and a \
        word in any of them stays exactly as spoken, never translated into a sibling \
        configured language ("mañá pola tarde" inside a Spanish sentence stays as is). Only \
        spellings from OUTSIDE the list — typically Galician written with Portuguese \
        orthography — get respelled into the closest configured language ("tínhamos, uma" → \
        "tiñamos, unha"), never dropping or reordering words.
        """
        if let detected, !detected.isEmpty {
            block += """
            \nThe transcriber labeled this transcript "\(detected)"; labels are unreliable \
            for close languages, trust the words themselves.
            """
        }
        return block
    }

    private static let technicalBlock = """
    Technical target: the text lands in a code editor or terminal. When the dictation reads \
    like code, a command or an identifier, output it verbatim: dictated symbols exactly as \
    spoken ("guión guión force" → "--force", "barra" → "/"), casing conventions applied, no \
    added prose punctuation or capitalization, never wrapped in backticks or quotes. Only \
    clearly conversational prose (a comment, a chat message) gets normal punctuation.
    """

    private static func vocabularyBlock(_ terms: [String]) -> String {
        """
        Exact spellings to enforce when a close-sounding or misspelled variant appears: \
        \(terms.joined(separator: ", "))
        """
    }

    private static func contextBlock(_ context: String) -> String {
        """
        The dictation CONTINUES an existing text; immediately before the cursor sits \
        (between ⟦⟧, possibly cut mid-sentence): ⟦\(context)⟧
        Match its language; start lowercase if it continues an unfinished sentence, \
        capitalized after a sentence end. Never repeat or complete that existing text, never \
        add a leading space or punctuation to attach it (the app handles spacing), and never \
        write beyond what was dictated — the context says how the new text attaches, never \
        what to write.
        """
    }
}
