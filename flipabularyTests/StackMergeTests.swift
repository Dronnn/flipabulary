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

    func testMergeRejectsUnknownAndDuplicateStackIDs() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        assertFailure(harness.library.mergeStacks([first.id, UUID()], named: "Merged", deleteOriginals: false))
        assertFailure(harness.library.mergeStacks([first.id, first.id], named: "Merged", deleteOriginals: false))
        XCTAssertNil(harness.library.stacks().first(where: { $0.name == "Merged" }))

        let result = try requireMerge([first.id, first.id, second.id], name: "Merged", deleteOriginals: false)
        XCTAssertEqual(result.stack.name, "Merged")
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

    func testMergeNameBoundaryAndCaseInsensitiveDuplicateCheck() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let survivor = harness.makeStack(name: "Café", isDefault: false)
        try harness.save()

        assertFailure(
            harness.library.mergeStacks([first.id, second.id], named: "CAFE", deleteOriginals: false)
        )

        let boundaryName = String(repeating: "x", count: 60)
        let result = try requireMerge([first.id, second.id], name: boundaryName, deleteOriginals: false)
        XCTAssertEqual(result.stack.name, boundaryName)
        XCTAssertNotNil(harness.library.stack(id: survivor.id))
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

    func testMergeCombinesMoreThanTwoStacksInOneGroup() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let third = harness.makeStack(name: "Third", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "cat", translation: "кошка", stack: second)
        harness.makeCard(word: "кошка", translation: "cat", stack: third, lifecycle: .learned, repeatCount: 4)
        harness.makeCard(word: "dog", translation: "собака", stack: third)
        try harness.save()

        let result = try requireMerge([first.id, second.id, third.id], name: "Merged", deleteOriginals: true)
        let cards = cards(in: result.stack)

        XCTAssertEqual(result.mergedCardCount, 2)
        XCTAssertEqual(result.duplicateCount, 2)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(result.removedStackCount, 3)
        XCTAssertEqual(cards.first(where: { $0.word == "кошка" })?.learningState?.repeatCount, 4)
        XCTAssertNil(harness.library.stack(id: first.id))
        XCTAssertNil(harness.library.stack(id: second.id))
        XCTAssertNil(harness.library.stack(id: third.id))
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
        learned.learningState?.stepIndex = LearningRules.defaultSteps.count
        learned.learningState?.reviewStageIndex = 2
        learned.learningState?.appliedMilestones = [0, 1]
        learned.learningState?.learnedAnchor = harness.clock.now
        learned.learningState?.lastGradedAt = harness.clock.now
        let expectedSnapshot = learned.snapshot
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.word, "кошка")
        XCTAssertEqual(card.translation, "cat")
        XCTAssertEqual(card.learningState?.lifecycle, .learned)
        XCTAssertEqual(card.learningState?.repeatCount, 4)
        XCTAssertEqual(card.learningState?.totalGrades, 12)
        XCTAssertEqual(card.snapshot, expectedSnapshot)
        XCTAssertEqual(card.learningState?.nextDueAt, due)
        XCTAssertEqual(result.duplicateCount, 1)
    }

    func testMergeKeepsMasteredProgressOverEarlierStageWithMoreAnswers() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let mastered = harness.makeCard(word: "cat", translation: "кошка", stack: first, lifecycle: .learned, repeatCount: 9)
        mastered.learningState?.stepIndex = LearningRules.defaultSteps.count
        mastered.learningState?.reviewStageIndex = LearningEngine.decayMilestones.count
        mastered.learningState?.appliedMilestones = Set(LearningEngine.decayMilestones.map(\.index))
        mastered.learningState?.nextDueAt = nil
        mastered.learningState?.totalGrades = 14
        let earlier = harness.makeCard(word: "cat", translation: "кошка", stack: second, lifecycle: .learned, repeatCount: 20, nextDueAt: harness.clock.now.addingTimeInterval(86_400))
        earlier.learningState?.totalGrades = 100
        earlier.learningState?.reviewStageIndex = 0
        let expected = mastered.snapshot
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let merged = try XCTUnwrap(result.stack.cards.first)
        XCTAssertEqual(result.stack.cards.count, 1)
        XCTAssertEqual(merged.snapshot, expected)
        XCTAssertTrue(merged.snapshot.isFullyMastered)
    }

    func testMergeTieBreaksUseGradesThenRepeatsThenLastGradedThenCreation() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let now = harness.clock.now

        let gradesLow = harness.makeCard(word: "grades", translation: "оценки", stack: first, lifecycle: .learned, repeatCount: 2)
        let gradesHigh = harness.makeCard(word: "grades", translation: "оценки", stack: second, lifecycle: .learned, repeatCount: 2)
        gradesLow.learningState?.totalGrades = 3
        gradesHigh.learningState?.totalGrades = 9

        let repeatsLow = harness.makeCard(word: "repeats", translation: "повторы", stack: first, lifecycle: .learned, repeatCount: 2)
        let repeatsHigh = harness.makeCard(word: "repeats", translation: "повторы", stack: second, lifecycle: .learned, repeatCount: 7)
        repeatsLow.learningState?.totalGrades = 5
        repeatsHigh.learningState?.totalGrades = 5

        let gradedEarly = harness.makeCard(word: "graded", translation: "оценено", stack: first, lifecycle: .learned, repeatCount: 3)
        let gradedLate = harness.makeCard(word: "graded", translation: "оценено", stack: second, lifecycle: .learned, repeatCount: 3)
        gradedEarly.learningState?.totalGrades = 5
        gradedLate.learningState?.totalGrades = 5
        gradedEarly.learningState?.lastGradedAt = now.addingTimeInterval(-3_600)
        gradedLate.learningState?.lastGradedAt = now.addingTimeInterval(-1_800)

        let older = harness.makeCard(
            word: "created",
            translation: "создано",
            stack: first,
            createdAt: now.addingTimeInterval(-200)
        )
        let newer = harness.makeCard(
            word: "created",
            translation: "создано",
            stack: second,
            createdAt: now.addingTimeInterval(-100)
        )
        older.sourceExample = "older wins"
        newer.sourceExample = "newer loses"
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let merged = cards(in: result.stack)

        XCTAssertEqual(merged.first(where: { $0.word == "grades" })?.learningState?.totalGrades, 9)
        XCTAssertEqual(merged.first(where: { $0.word == "repeats" })?.learningState?.repeatCount, 7)
        XCTAssertEqual(
            merged.first(where: { $0.word == "graded" })?.learningState?.lastGradedAt,
            now.addingTimeInterval(-1_800)
        )
        XCTAssertEqual(merged.first(where: { $0.word == "created" })?.sourceExample, "older wins")
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

    func testMergeDoesNotCopyWordSpecificFieldsFromOppositeDirectionDuplicate() throws {
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
        loser.phonetic = "kæt"
        loser.partOfSpeech = "noun"
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertNil(card.phonetic)
        XCTAssertNil(card.partOfSpeech)
    }

    func testMergeTreatsBlankFieldsAsMissing() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4
        )
        winner.sourceExample = "   "
        winner.translatedExample = ""
        winner.phonetic = " "
        winner.partOfSpeech = ""
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        loser.sourceExample = "The cat sat."
        loser.translatedExample = "Кошка сидела."
        loser.phonetic = "kæt"
        loser.partOfSpeech = "noun"
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.sourceExample, "The cat sat.")
        XCTAssertEqual(card.translatedExample, "Кошка сидела.")
        XCTAssertEqual(card.phonetic, "kæt")
        XCTAssertEqual(card.partOfSpeech, "noun")
    }

    func testMergeDeduplicatesTagsCaseInsensitively() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4,
            tags: ["Travel"]
        )
        harness.makeCard(word: "cat", translation: "кошка", stack: second, tags: ["travel", "B1"])
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.tags.count, 2)
        XCTAssertEqual(
            Set(card.tags.map { SearchNormalizer.normalize($0.name) }),
            ["travel", "b1"]
        )
    }

    func testMergeFillsFieldsFromSeveralDuplicates() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let third = harness.makeStack(name: "Third", isDefault: false)
        harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4
        )
        let secondCard = harness.makeCard(word: "cat", translation: "кошка", stack: second)
        secondCard.sourceExample = "The cat sat."
        secondCard.phonetic = "kæt"
        let thirdCard = harness.makeCard(word: "cat", translation: "кошка", stack: third)
        thirdCard.translatedExample = "Кошка сидела."
        thirdCard.partOfSpeech = "noun"
        thirdCard.tags = [try XCTUnwrap(harness.library.findOrCreateTag(named: "animals"))]
        try harness.save()

        let result = try requireMerge([first.id, second.id, third.id], name: "Merged", deleteOriginals: false)
        let card = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertEqual(card.sourceExample, "The cat sat.")
        XCTAssertEqual(card.phonetic, "kæt")
        XCTAssertEqual(card.translatedExample, "Кошка сидела.")
        XCTAssertEqual(card.partOfSpeech, "noun")
        XCTAssertEqual(card.tags.map(\.name), ["animals"])
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
        let due = harness.clock.now.addingTimeInterval(7_200)
        let winner = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: first,
            lifecycle: .learned,
            repeatCount: 4,
            nextDueAt: due
        )
        winner.learningState?.totalGrades = 12
        winner.learningState?.mistakeReturn = true
        winner.learningState?.appliedMilestones = [1, 2]
        winner.learningState?.rulesVersion = 12
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
        XCTAssertEqual(copy.learningState?.totalGrades, 12)
        XCTAssertEqual(copy.learningState?.nextDueAt, due)
        XCTAssertEqual(copy.learningState?.mistakeReturn, true)
        XCTAssertEqual(copy.learningState?.appliedMilestones, [1, 2])
        XCTAssertEqual(copy.learningState?.rulesVersion, 12)
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

    func testKeepOriginalsSelectsMergedStackAndLeavesScopeReferencesAlone() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let unrelated = harness.makeStack(name: "Unrelated", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        harness.preferences.preferences.selectedStackID = unrelated.id
        harness.preferences.preferences.widgetDefaults.stackID = first.id
        harness.preferences.preferences.reminders.stackID = second.id
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)

        XCTAssertEqual(harness.preferences.preferences.selectedStackID, result.stack.id)
        XCTAssertEqual(harness.preferences.preferences.widgetDefaults.stackID, first.id)
        XCTAssertEqual(harness.preferences.preferences.reminders.stackID, second.id)
    }

    func testMergeCopiesCardsWithMissingLearningState() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let card = harness.makeCard(word: "cat", translation: "кошка", stack: first, lifecycle: .learned, repeatCount: 4)
        card.learningState = nil
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let copy = try XCTUnwrap(cards(in: result.stack).first(where: { $0.word == "cat" }))

        XCTAssertEqual(copy.learningState?.lifecycle, .new)
        XCTAssertEqual(copy.learningState?.repeatCount, 0)
    }

    func testMergePublishesUpdatedWidgetSnapshot() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "cat", translation: "кошка", stack: second)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)
        let snapshot = try XCTUnwrap(harness.snapshotStore.load())
        let stackSnapshot = try XCTUnwrap(snapshot.stacks.first(where: { $0.id == result.stack.id }))

        XCTAssertEqual(stackSnapshot.name, "Merged")
        XCTAssertEqual(stackSnapshot.savedCount, 2)
        XCTAssertEqual(Set(snapshot.stacks.map(\.id)).contains(first.id), false)
        XCTAssertEqual(Set(snapshot.stacks.map(\.id)).contains(second.id), false)
    }

    func testMergeEndsActiveSessionForRemovedStackSafely() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        try harness.save()

        let session = try startReview(first)
        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)
        harness.review.repair(session)

        XCTAssertEqual(session.status, .completed)
        XCTAssertNotNil(harness.library.stack(id: result.stack.id))
        XCTAssertNotNil(harness.library.stack(id: myWords.id))
        XCTAssertNil(harness.library.stack(id: first.id))
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

    func testDeleteOriginalsProtectsDefaultLoserWhenOtherStackWins() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        let defaultCard = harness.makeCard(word: "cat", translation: "кошка", stack: myWords)
        let otherCard = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: other,
            lifecycle: .learned,
            repeatCount: 5
        )
        harness.addEvent(to: defaultCard, grade: .good, at: harness.clock.now)
        try harness.save()

        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)
        let mergedCard = try XCTUnwrap(cards(in: result.stack).first)

        XCTAssertNotNil(harness.library.stack(id: myWords.id))
        XCTAssertNil(harness.library.stack(id: other.id))
        XCTAssertEqual(myWords.cards.map(\.id), [defaultCard.id])
        XCTAssertEqual(mergedCard.id, otherCard.id)
        XCTAssertEqual(mergedCard.learningState?.repeatCount, 5)
        XCTAssertEqual(defaultCard.reviewEvents.count, 1)
        XCTAssertTrue(mergedCard.reviewEvents.isEmpty)
    }

    func testDeleteOriginalsMovesLoserEventsToCopiedDefaultWinner() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let other = harness.makeStack(name: "Other", isDefault: false)
        let defaultCard = harness.makeCard(
            word: "cat",
            translation: "кошка",
            stack: myWords,
            lifecycle: .learned,
            repeatCount: 6
        )
        let loser = harness.makeCard(word: "cat", translation: "кошка", stack: other)
        harness.addEvent(to: defaultCard, grade: .good, at: harness.clock.now.addingTimeInterval(-120))
        harness.addEvent(to: loser, grade: .good, at: harness.clock.now)
        try harness.save()

        let result = try requireMerge([myWords.id, other.id], name: "Merged", deleteOriginals: true)
        let copy = try XCTUnwrap(cards(in: result.stack).first)
        let events = try harness.context.fetch(FetchDescriptor<ReviewEvent>())

        XCTAssertEqual(defaultCard.reviewEvents.count, 1)
        XCTAssertEqual(copy.reviewEvents.count, 1)
        XCTAssertEqual(Set(events.map(\.cardID)), [defaultCard.id, copy.id])
    }

    func testDeleteOriginalsProtectsDefaultCardsWhenSeveralStacksAreSelected() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let defaultCard = harness.makeCard(word: "cat", translation: "кошка", stack: myWords)
        harness.makeCard(word: "cat", translation: "кошка", stack: first, lifecycle: .learned, repeatCount: 3)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        try harness.save()

        let result = try requireMerge([myWords.id, first.id, second.id], name: "Merged", deleteOriginals: true)

        XCTAssertNotNil(harness.library.stack(id: myWords.id))
        XCTAssertNil(harness.library.stack(id: first.id))
        XCTAssertNil(harness.library.stack(id: second.id))
        XCTAssertEqual(myWords.cards.map(\.id), [defaultCard.id])
        XCTAssertEqual(result.removedStackCount, 2)
        XCTAssertEqual(cards(in: result.stack).count, 2)
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

    func testDeleteOriginalsLeavesUnrelatedScopeReferencesAlone() throws {
        let first = harness.makeStack(name: "First", isDefault: false)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let unrelated = harness.makeStack(name: "Unrelated", isDefault: false)
        harness.makeCard(word: "cat", translation: "кошка", stack: first)
        harness.makeCard(word: "dog", translation: "собака", stack: second)
        harness.preferences.preferences.widgetDefaults.stackID = unrelated.id
        harness.preferences.preferences.reminders.stackID = unrelated.id
        try harness.save()

        _ = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: true)

        XCTAssertEqual(harness.preferences.preferences.widgetDefaults.stackID, unrelated.id)
        XCTAssertEqual(harness.preferences.preferences.reminders.stackID, unrelated.id)
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
        let second = harness.makeStack(name: "Second", isDefault: false)
        try harness.save()

        let result = try requireMerge([first.id, second.id], name: "Merged", deleteOriginals: false)
        let merged = result.stack

        XCTAssertEqual(merged.cardsPerSession, 20)
        XCTAssertEqual(merged.newCardsPerDay, 10)
        XCTAssertTrue(merged.shuffleOrder)
        XCTAssertEqual(merged.presentationMode, .frontFirst)
        XCTAssertEqual(merged.steps, LearningRules.defaultSteps)
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

    private func startReview(_ stack: VocabularyStack) throws -> ReviewSession {
        switch harness.review.requestReview(scopeID: stack.id) {
        case .started(let id), .existing(let id):
            return try XCTUnwrap(harness.review.session(id: id))
        case .failure(let message):
            XCTFail(message)
            throw NSError(domain: "StackMergeTests", code: 1)
        case .empty, .needsScope:
            XCTFail("Expected a review session")
            throw NSError(domain: "StackMergeTests", code: 2)
        }
    }

    private func mergeKey(_ word: String, _ translation: String) -> String {
        let pair = [
            SearchNormalizer.normalize(word),
            SearchNormalizer.normalize(translation)
        ].sorted()
        return pair.joined(separator: "\u{1f}")
    }
}
