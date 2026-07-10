import Foundation

/// Deterministic spelling fixes applied to the raw transcript before the refiner sees it.
/// The dictionary biases Whisper and the refiner enforces spellings, but both are
/// probabilistic; a known mishearing ("cloud" → "Claude") deserves a guaranteed fix that
/// costs no tokens and keeps working when the refiner is down.
enum Corrections {
    /// Replaces whole-word occurrences of each trigger (case-insensitive) with its exact
    /// replacement. Longer triggers run first so "git hub actions" wins over "git hub".
    static func apply(_ corrections: [String: String], to text: String) -> String {
        guard !corrections.isEmpty, !text.isEmpty else { return text }
        var result = text
        for (trigger, replacement) in corrections.sorted(by: { $0.key.count > $1.key.count }) {
            let trimmed = trigger.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // \b is ASCII-minded; explicit letter/digit lookarounds keep accented words
            // whole ("ano" must not match inside "año" nor "mano").
            let pattern = "(?<![\\p{L}\\p{N}])"
                + NSRegularExpression.escapedPattern(for: trimmed)
                + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        return result
    }
}
