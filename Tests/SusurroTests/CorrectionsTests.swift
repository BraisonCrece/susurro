import XCTest
@testable import Susurro

final class CorrectionsTests: XCTestCase {
    func testReplacesWholeWordCaseInsensitively() {
        let fixed = Corrections.apply(["clod": "Claude"], to: "le pregunté a Clod y clod contestó")
        XCTAssertEqual(fixed, "le pregunté a Claude y Claude contestó")
    }

    func testNeverTouchesTheInsideOfAWord() {
        let corrections = ["ano": "año"]
        XCTAssertEqual(Corrections.apply(corrections, to: "la mano en el piano"),
                       "la mano en el piano")
        XCTAssertEqual(Corrections.apply(corrections, to: "el ano pasado"), "el año pasado")
    }

    func testAccentedNeighborsCountAsLetters() {
        // \b would see "í" as a boundary and mangle "cafeína"; the letter-class
        // lookarounds treat accented letters as the word interior they are.
        XCTAssertEqual(Corrections.apply(["cafe": "café"], to: "la cafeína del cafe"),
                       "la cafeína del café")
    }

    func testLongerTriggersWin() {
        let corrections = ["git hub": "GitHub", "git hub actions": "GitHub Actions"]
        XCTAssertEqual(Corrections.apply(corrections, to: "configura git hub actions hoy"),
                       "configura GitHub Actions hoy")
    }

    func testMultiWordTriggerAndPunctuationBoundary() {
        XCTAssertEqual(Corrections.apply(["white box": "Whitebox"], to: "en white box, mañana"),
                       "en Whitebox, mañana")
    }

    func testReplacementWithTemplateCharactersIsLiteral() {
        XCTAssertEqual(Corrections.apply(["variable": "$HOME"], to: "usa variable"), "usa $HOME")
    }

    func testEmptyInputsPassThrough() {
        XCTAssertEqual(Corrections.apply([:], to: "hola"), "hola")
        XCTAssertEqual(Corrections.apply(["a": "b"], to: ""), "")
        XCTAssertEqual(Corrections.apply(["  ": "b"], to: "hola"), "hola")
    }
}

final class LeadingSpaceTests: XCTestCase {
    func testAddsSpaceAfterSentenceEnd() {
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "Además mañana",
                                                              after: "…el jueves."),
                       " Además mañana")
    }

    func testNoSpaceWithoutContextOrAfterWhitespace() {
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "Hola", after: nil), "Hola")
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "Hola", after: "línea\n"), "Hola")
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "Hola", after: "palabra "), "Hola")
    }

    func testNoSpaceAfterOpeners() {
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "hola", after: "("), "hola")
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "hola", after: "¿"), "hola")
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "usuario", after: "@"), "usuario")
    }

    func testOpeningQuestionMarkGetsSpace() {
        XCTAssertEqual(DictationPipeline.applyingLeadingSpace(to: "¿Vienes?", after: "Dime."),
                       " ¿Vienes?")
    }
}

final class SpeechGateTests: XCTestCase {
    private func recording(duration: TimeInterval = 2, peak: Float = 0.1,
                           active: TimeInterval = 1) -> Recording {
        Recording(fileURL: URL(fileURLWithPath: "/dev/null"), duration: duration,
                  peakLevel: peak, activeDuration: active)
    }

    func testNormalSpeechPasses() {
        XCTAssertTrue(recording().hasSpeech)
    }

    func testTooShortTooQuietOrTransientOnlyIsDiscarded() {
        XCTAssertFalse(recording(duration: 0.3).hasSpeech)
        XCTAssertFalse(recording(peak: 0.001).hasSpeech)
        XCTAssertFalse(recording(active: 0.1).hasSpeech)
    }
}

final class EnforcedVocabularyTests: XCTestCase {
    func testMergesDictionaryAndCorrectionTargetsWithoutDuplicates() {
        let config = Config(groqApiKey: "", transcriptionModel: "", cleanupModel: "",
                            languages: [], systemPrompt: "", useCursorContext: true,
                            dictionary: ["Whitebox", "Sorbet"],
                            corrections: ["white box": "Whitebox", "clod": "Claude"],
                            technicalApps: [])
        XCTAssertEqual(config.enforcedVocabulary, ["Whitebox", "Sorbet", "Claude"])
    }
}
