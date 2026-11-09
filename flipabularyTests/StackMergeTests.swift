import XCTest
import SwiftData
@testable import flipabulary

@MainActor
final class StackMergeTests: XCTestCase {
    private var harness: TestHarness!

    override func setUp() async throws {
        harness = try TestHarness()
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    // MARK: Validation

    func testMergeRejectsFewerThanTwoStacks() throws {
        let stack = harness.makeStack(name: "One", isDefault: true)
        try harness.save()

        assertFailure(harness.library.mergeStacks([], named: "Merged", deleteOriginals: false))
        assertFailure(harness.library.mergeStacks([stack.id], named: "Merged", deleteOriginals: false))
        XCTAssertNil(harness.library.stacks().first(where: { $0.name == "Merged" }))
    }

    func testMergeRejectsInvalidAndDuplicateNames() throws {
        let first = harness.makeStack(name: "First", isDefault: true)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let survivor = harness.makeStack(name: "Survivor", isDefault: false)
        try harness.save()

        assertFailure(harness.library.mergeStacks([first.id, second.id], named: "   ", deleteOriginals: false))
        assertFailure(
            harness.library.mergeStacks(
                [first.id, second.id],
                named: String(repeating: "x", count: 61),
                deleteOriginals: false
            )
        )
        assertFailure(
            harness.library.mergeStacks(
                [first.id, second.id],
                named: survivor.name,
                deleteOriginals: false
            )
        )
    }

    func testMergeAllowsReusingNameOfStackBeingDeleted() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "First", deleteOriginals: true)
        XCTAssertEqual(result.stack.name, "First")
        XCTAssertNil(harness.library.stack(id: first.id))
        XCTAssertNil(harness.library.stack(id: second.id))
    }

    func testMergeDoesNotReuseDefaultStackName() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        try harness.save()

        assertFailure(
            harness.library.mergeStacks([myWords.id, other.id], named: "My words", deleteOriginals: true)
        )
        XCTAssertNotNil(harness.library.stack(id: myWords.id))
    }

    func testMergeRejectsSelectedNameWhenKeepingOriginals() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        assertFailure(
            harness.library.mergeStacks([first.id, second.id], named: "First", deleteOriginals: false)
        )
        XCTAssertNotNil(harness.library.stack(id: first.id))
    }

    // MARK: Deduplication

    func testMergeDeduplicatesDirectAndCrossDirectionMatches() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: first)
        harness.makeCard(word: "cat", translation: "кошка", stack: second)
        harness.makeCard(word: "кошка", translation: "cat", stack: second)
        harness.makeCard(word: "bird", translation: "птица", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)

        XCTAssertEqual(result.mergedCardCount, 3)
        XCTAssertEqual(result.duplicateCount, 2)
        XCTAssertEqual(cards(in: result.stack).count, 3)
        XCTAssertEqual(Set(cards(in: result.stack).map { mergeKey($0.word, $0.translation) }).count, 3)
    }

    func testMergeDeduplicatesCaseWidthAndDiacriticInsensitively() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "Café", translation: "coffee", stack: first)
        harness.makeCard(word: "ＣＡＦＥ", translation: "ＣＯＦＦＥＥ", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        XCTAssertEqual(result.mergedCardCount, 1)
        XCTAssertEqual(cards(in: result.stack).count, 1)
    }

    func testMergeDeduplicatesCardsInsideOneStack() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "CAT", translation: "КОШКА", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        XCTAssertEqual(result.mergedCardCount, 2)
        XCTAssertEqual(result.duplicateCount, 1)
    }

    func testMergeKeepsCardsThatOnlyOverlapOnOneSide() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "cat", translation: "кот", stack: second)
        harness.makeCard(word: "кошка", translation: "kitty", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        XCTAssertEqual(result.mergedCardCount, 3)
        XCTAssertEqual(result.duplicateCount, 0)
    }

    // MARK: Card selection and field merging

    func testMergeKeepsMostProgressedCardAndCopiesItsProgress() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let due = harness.clock.now.addingTimeInterval(3_600)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        let learned = harness.makeCard(
            word: "кошка",
            translation: "cat",
            stack: second,
            lifecycle: .learned,
            repeatCount: 4,
            nextDueAt: due
        )
        learned.learningState?.totalGrades = 12
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.word, "кошка")
        XCTAssertEqual(card.translation, "cat")
        XCTAssertEqual(card.learningState?.lifecycle, .learned)
        XCTAssertEqual(card.learningState?.repeatCount, 4)
        XCTAssertEqual(card.learningState?.totalGrades, 12)
        XCTAssertEqual(card.learningState?.nextDueAt, due)
        XCTAssertEqual(result.duplicateCount, 1)
    }

    func testMergeFillsMissingFieldsUnionsTagsAndKeepsDifficult() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 3,
            tags: ["core"]
        )
        let loser = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: second,
            tags: ["animals"]
        )
        loser.sourceExample = "The cat sat."
        loser.translatedExample = "Кошка сидела."
        loser.phonetic = "kæt"
        loser.partOfSpeech = "noun"
        loser.difficultOverride = true
        winner.difficultOverride = nil
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.sourceExample, "The cat sat.")
        XCTAssertEqual(card.translatedExample, "Кошка сидела.")
        XCTAssertEqual(card.phonetic, "kæt")
        XCTAssertEqual(card.partOfSpeech, "noun")
        XCTAssertEqual(Set(card.tags.map(\.name)), ["core", "animals"])
        XCTAssertEqual(card.difficultOverride, true)
    }

    func testMergeSwapsExamplesForOppositeDirectionDuplicate() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(
            word: "кошка",
            translation: "cat",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4
        )
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        loser.sourceExample = "The cat sat."
        loser.translatedExample = "Кошка сидела."
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.word, "кошка")
        XCTAssertEqual(card.translation, "cat")
        XCTAssertEqual(card.sourceExample, "Кошка сидела.")
        XCTAssertEqual(card.translatedExample, "The cat sat.")
    }

    func testMergeKeepsWinnerFieldsWhenDuplicatesDisagree() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 3
        )
        winner.sourceExample = "winner example"
        winner.phonetic = "winner phonetic"
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        loser.sourceExample = "loser example"
        loser.phonetic = "loser phonetic"
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.sourceExample, "winner example")
        XCTAssertEqual(card.phonetic, "winner phonetic")
    }

    // MARK: Keep originals

    func testKeepOriginalsLeavesSourcesUntouchedAndCopiesProgress() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4
        )
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        loser.sourceExample = "The cat sat."
        try harness.save()

        let firstCardIDs = Set(first.cards.map(\.id))
        let secondCardIDs = Set(second.cards.map(\.id))
        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)

        XCTAssertEqual(Set(first.cards.map(\.id)), firstCardIDs)
        XCTAssertEqual(Set(second.cards.map(\.id)), secondCardIDs)
        XCTAssertNil(winner.sourceExample)
        XCTAssertEqual(result.removedStackCount, 0)

        let copy = try XCTUnwrap(cards(in: result.stack).first)
        XCTAssertNotEqual(copy.id, winner.id)
        XCTAssertNotEqual(copy.id, loser.id)
        XCTAssertEqual(copy.learningState?.lifecycle, .learned)
        XCTAssertEqual(copy.learningState?.repeatCount, 4)
        XCTAssertEqual(copy.sourceExample, "The cat sat.")
        XCTAssertEqual(harness.library.stacks().count, 3)
    }

    func testKeepOriginalsDoesNotCopyReviewHistory() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let card = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learning,
            repeatCount: 1
        )
        harness.makeCard(word: "cat", translation: "кошка", stack: second)
        harness.addEvent(to: card, grade: .good, at: harness.clock.now)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let copy = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.reviewEvents.count, 1)
        XCTAssertTrue(copy.reviewEvents.isEmpty)
    }

    func testKeepOriginalsDoesNotChangeWidgetWordSetReferences() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let card = harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        harness.preferences.preferences.widgetWordSets = [
            WidgetWordSet(name: "Set", cardIDs: [card.id])
        ]
        try harness.save()

        _ = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        XCTAssertEqual(harness.preferences.preferences.widgetWordSets.first?.cardIDs, [card.id])
    }

    // MARK: Delete originals

    func testDeleteOriginalsMovesWinnerRemovesStacksAndReassignsDuplicateHistory() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 5
        )
        let loser = harness.makeCard(
            word: "кошка",
            translation: "cat",
            stack: second,
            lifecycle: .learning,
            repeatCount: 2
        )
        harness.addEvent(to: winner, grade: .good, at: harness.clock.now.addingTimeInterval(-60))
        harness.addEvent(to: loser, grade: .good, at: harness.clock.now)
        try harness.save()

        let winnerID = winner.id
        let loserID = loser.id
        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(result.removedStackCount, 2)
        XCTAssertNil(harness.library.stack(id: first.id))
        XCTAssertNil(harness.library.stack(id: second.id))
        XCTAssertNil(harness.library.card(id: loserID))

        let mergedCard = try XCTUnwrap(cards(in: result.stack).first)
        XCTAssertEqual(mergedCard.id, winnerID)
        XCTAssertEqual(mergedCard.word, "cat")
        XCTAssertEqual(mergedCard.translation, "кошка")
        XCTAssertEqual(mergedCard.learningState?.lifecycle, .learned)
        XCTAssertEqual(mergedCard.learningState?.repeatCount, 5)
        XCTAssertNotEqual(mergedCard.id, loserID)

        let events = try harness.context.fetch(FetchDescriptor<ReviewEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.cardID == mergedCard.id })
        XCTAssertTrue(events.allSatisfy { $0.card?.id == mergedCard.id })
    }

    func testDeleteOriginalsMovesTheWinningOriginalCardWhenItIsNotFromDefault() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 5
        )
        harness.makeCard(word: "кошка", translation: "cat", stack: second)
        try harness.save()

        let winnerID = winner.id
        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)
        let mergedCard = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(mergedCard.id, winnerID)
        XCTAssertEqual(mergedCard.stack?.id, result.stack.id)
    }

    func testDeleteOriginalsNeverDeletesDefaultStackAndCopiesItsCards() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        let defaultCard = harness.makeCard(word: "cat", translation: "кошка", stack: myWords)
        harness.makeCard(word: "dog", translation: "собака", stack: other)
        try harness.save()

        let defaultCardID = defaultCard.id
        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)

        XCTAssertNotNil(harness.library.stack(id: myWords.id))
        XCTAssertNil(harness.library.stack(id: other.id))
        XCTAssertEqual(result.removedStackCount, 1)
        XCTAssertEqual(result.stack.isDefault, false)
        XCTAssertEqual(myWords.cards.map(\.id), [defaultCardID])
        XCTAssertEqual(cards(in: result.stack).count, 2)
        XCTAssertFalse(cards(in: result.stack).contains(where: { $0.id == defaultCardID }))
    }

    func testDeleteOriginalsKeepsDefaultWinnerInPlaceAndCopiesIt() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        let defaultCard = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: myWords,
            lifecycle: .learned,
            repeatCount: 6
        )
        harness.makeCard(word: "кошка", translation: "cat", stack: other)
        try harness.save()

        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)
        let copy = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(myWords.cards.count, 1)
        XCTAssertEqual(myWords.cards.first?.id, defaultCard.id)
        XCTAssertNotEqual(copy.id, defaultCard.id)
        XCTAssertEqual(copy.learningState?.lifecycle, .learned)
        XCTAssertEqual(copy.learningState?.repeatCount, 6)
    }

    // MARK: Preferences and integrations

    func testDeleteOriginalsRepointsStackReferencesAndRemapsWidgetSets() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let unrelated = harness.makeStack(name: "Unrelated", isDefault: false)
        let winner = harness.makeCard(word: "cat", translation: "кошка", stack: first, lifecycle: .learned, repeatCount: 2)
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        let unrelatedCard = harness.makeCard(word: "dog", translation: "собака", stack: unrelated)
        harness.preferences.preferences.selectedStackID = first.id
        harness.preferences.preferences.widgetDefaults.stackID = second.id
        harness.preferences.preferences.reminders.stackID = first.id
        harness.preferences.preferences.widgetWordSets = [
            WidgetWordSet(name: "One", cardIDs: [loser.id, winner.id, unrelatedCard.id]),
            WidgetWordSet(name: "Two", cardIDs: [loser.id, loser.id])
        ]
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(harness.preferences.preferences.selectedStackID, result.stack.id)
        XCTAssertEqual(harness.preferences.preferences.widgetDefaults.stackID, result.stack.id)
        XCTAssertEqual(harness.preferences.preferences.reminders.stackID, result.stack.id)
        XCTAssertEqual(
            harness.preferences.preferences.widgetWordSets[0].cardIDs,
            [winner.id, unrelatedCard.id]
        )
        XCTAssertEqual(harness.preferences.preferences.widgetWordSets[1].cardIDs, [winner.id])
        XCTAssertNotNil(harness.library.stack(id: myWords.id))
    }

    func testDeleteOriginalsLeavesDefaultReferencesOnDefaultStack() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: myWords)
        harness.makeCard(word: "dog", translation: "собака", stack: other)
        harness.preferences.preferences.widgetDefaults.stackID = myWords.id
        harness.preferences.preferences.reminders.stackID = myWords.id
        try harness.save()

        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(harness.preferences.preferences.widgetDefaults.stackID, myWords.id)
        XCTAssertEqual(harness.preferences.preferences.reminders.stackID, myWords.id)
        XCTAssertNotEqual(result.stack.id, myWords.id)
    }

    func testDeleteOriginalsDoesNotRemapWidgetSetsForDefaultCardsThatStay() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        let defaultCard = harness.makeCard(word: "cat", translation: "кошка", stack: myWords)
        let otherCard = harness.makeCard(word: "dog", translation: "собака", stack: other)
        harness.preferences.preferences.widgetWordSets = [
            WidgetWordSet(name: "Default", cardIDs: [defaultCard.id]),
            WidgetWordSet(name: "Other", cardIDs: [otherCard.id])
        ]
        try harness.save()

        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(harness.preferences.preferences.widgetWordSets[0].cardIDs, [defaultCard.id])
        XCTAssertEqual(harness.preferences.preferences.widgetWordSets[1].cardIDs, [otherCard.id])
        XCTAssertTrue(cards(in: result.stack).contains(where: { $0.id == otherCard.id }))
    }

    func testMergeUsesStandardSettingsAndAppearsAtTheTop() throws {
        let first = harness.makeStack(
            name: "First",
            isDefault: false,
            cardsPerSession: 77,
            newCardsPerDay: 42,
            shuffle: false,
            translationFirst: true,
            steps: [30, 600]
        )
        first.customRules = LearningRules.default
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let merged = result.stack

        XCTAssertEqual(merged.cardsPerSession, 20)
        XCTAssertEqual(merged.newCardsPerDay, 10)
        XCTAssertTrue(merged.shuffleOrder)
        XCTAssertEqual(merged.presentationMode, .frontFirst)
        XCTAssertEqual(merged.steps, LearningRules.defaultSteps)
        XCTAssertNil(merged.customRules)
        XCTAssertEqual(harness.library.stacks().first?.id, merged.id)
        XCTAssertEqual(merged.isDefault, false)
    }

    func testMergeDoesNotTouchUnselectedStacksOrDuplicateAcrossThem() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let other = harness.makeStack(name: "Other", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "cat", translation: "кошка", stack: second)
        harness.makeCard(word: "cat", translation: "кошка", stack: other)
        try harness.save()

        let otherCardIDs = Set(other.cards.map(\.id))
        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(Set(other.cards.map(\.id)), otherCardIDs)
        XCTAssertEqual(cards(in: result.stack).count, 1)
        XCTAssertEqual(harness.library.stacks().map(\.name).sorted(), ["Merged", "Other"])
    }

    func testMergeWithNoCardsCreatesAnEmptyStack() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)
        XCTAssertEqual(result.mergedCardCount, 0)
        XCTAssertEqual(result.duplicateCount, 0)
        XCTAssertEqual(cards(in: result.stack).count, 0)
        XCTAssertTrue(harness.library.stack(id: first.id) == nil)
        XCTAssertTrue(harness.library.stack(id: second.id) == nil)
    }

    // MARK: Helpers

    private func requireMerge(
        _ ids: [UUID],
        name: String,
        deleteOriginals: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> StackMergeResult {
        switch harness.library.mergeStacks(ids, named: name, deleteOriginals: deleteOriginals) {
        case .success(let result):
            return result
        case .failure(let error):
            XCTFail("Merge failed: \(error)", file: file, line: line)
            throw error
        }
    }

    private func assertFailure(
        _ result: Result<StackMergeResult, LibraryWriteError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected merge to fail", file: file, line: line)
        case .failure:
            break
        }
    }

    private func cards(in stack: VocabularyStack) -> [VocabularyCard] {
        harness.library.stack(id: stack.id)?.cards ?? []
    }

    private func mergeKey(_ word: String, _ translation: String) -> String {
        let pair = [
            SearchNormalizer.normalize(word),
            SearchNormalizer.normalize(translation)
        ].sorted()
        return pair.joined(separator: "\u{1f}")
    }
}
