import XCTest
@testable import flipabulary

final class ValidationTests: XCTestCase {
    func testRequiredAndOptionalFieldRules() {
        var draft = CardDraft()
        var validation = draft.validateBasic(stackExists: true)
        XCTAssertEqual(validation.wordError, "Enter a word.")
        XCTAssertEqual(validation.translationError, "Enter a translation.")
        XCTAssertNil(validation.sourceExampleError)
        XCTAssertNil(validation.translatedExampleError)

        draft.word = "  word  "
        draft.translation = "  translation  "
        draft.sourceExample = "  optional example  "
        draft.stackID = UUID()
        validation = draft.validateBasic(stackExists: true)
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(draft.trimmedWord, "word")
        XCTAssertEqual(draft.trimmedTranslation, "translation")
        XCTAssertEqual(draft.trimmedSourceExample, "optional example")
    }

    func testGraphemeClusterLimits() {
        var draft = CardDraft()
        draft.word = String(repeating: "👨‍👩‍👧‍👦", count: 200)
        draft.translation = String(repeating: "é", count: 201)
        draft.stackID = UUID()
        let validation = draft.validateBasic(stackExists: true)
        XCTAssertNil(validation.wordError)
        XCTAssertNotNil(validation.translationError)
        XCTAssertEqual(draft.word.count, 200)
        XCTAssertEqual(draft.translation.count, 201)

        draft.translation = "ok"
        draft.sourceExample = String(repeating: "a", count: 2_001)
        draft.translatedExample = String(repeating: "b", count: 2_001)
        let examples = draft.validateBasic(stackExists: true)
        XCTAssertNotNil(examples.sourceExampleError)
        XCTAssertNotNil(examples.translatedExampleError)
    }

    func testMissingStackAndLongTagNames() {
        var draft = CardDraft()
        draft.word = "word"
        draft.translation = "translation"
        draft.tagNames = [String(repeating: "x", count: 61)]
        let validation = draft.validateBasic(stackExists: false)
        XCTAssertNotNil(validation.stackError)
        XCTAssertNotNil(validation.tagError)
    }

    func testTagNormalizationDeduplicatesCaseInsensitively() {
        var draft = CardDraft()
        draft.tagNames = [" Work ", "work", "WORK", "B1", "", "  "]
        XCTAssertEqual(draft.normalizedTagNames, ["Work", "B1"])
    }

    func testDurationListValidation() {
        XCTAssertEqual(LearningRules.validatedSteps([]), LearningRules.defaultSteps)
        XCTAssertEqual(LearningRules.validatedSteps([0]), LearningRules.defaultSteps)
        XCTAssertEqual(LearningRules.validatedSteps([-1]), LearningRules.defaultSteps)
        XCTAssertEqual(LearningRules.validatedSteps([60, 60]), LearningRules.defaultSteps)
        XCTAssertEqual(LearningRules.validatedSteps([600, 60]), LearningRules.defaultSteps)
        XCTAssertEqual(LearningRules.validatedSteps([60, 600, 86_400]), [60, 600, 86_400])
        XCTAssertEqual(LearningRules.validatedSteps([30, 120, 3_000]), [30, 120, 3_000])
    }

    func testNumericSettingBounds() {
        var rules = LearningRules.default
        rules.correctThreshold = 0
        rules.returnBelow = 0
        XCTAssertEqual(rules.normalized.correctThreshold, 1)
        XCTAssertEqual(rules.normalized.returnBelow, 1)

        var config = SessionConfig(
            stackID: UUID(),
            cardsPerSession: 0,
            newCardsPerDay: 999,
            shuffle: true,
            translationFirst: false,
            steps: [],
            rules: rules,
            seed: 1
        ).normalized()
        XCTAssertEqual(config.cardsPerSession, 1)
        XCTAssertEqual(config.newCardsPerDay, 100)
        XCTAssertEqual(config.steps, LearningRules.defaultSteps)

        config.cardsPerSession = 999
        config.newCardsPerDay = -5
        let normalized = config.normalized()
        XCTAssertEqual(normalized.cardsPerSession, 100)
        XCTAssertEqual(normalized.newCardsPerDay, 0)
    }
}
