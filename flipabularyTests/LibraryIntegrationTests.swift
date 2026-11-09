import XCTest
import SwiftData
@testable import flipabulary

@MainActor
final class LibraryIntegrationTests: XCTestCase {
    private var harness: TestHarness!

    override func setUp() async throws {
        harness = try TestHarness()
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    // MARK: IT-01

    func testCreateEditMoveDeleteAndRelationshipsSurviveRefetch() throws {
        let stack = harness.makeStack(name: "My words")
        let other = harness.makeStack(name: "Spanish B1", isDefault: false)
        try harness.save()

        var draft = CardDraft()
        draft.word = "  café  "
        draft.translation = "  кофейня  "
        draft.sourceExample = "A café."
        draft.translatedExample = "Кафе."
        draft.stackID = stack.id
        draft.tagNames = ["Travel", "travel", "B1"]

        let result = harness.library.saveCard(draft: draft, existing: nil)
        guard case .success(let card) = result else {
            return XCTFail("Save failed: \(result)")
        }
        XCTAssertEqual(card.word, "café")
        XCTAssertEqual(card.translation, "кофейня")
        XCTAssertEqual(Set(card.tags.map(\.name)), ["Travel", "B1"])
        XCTAssertEqual(card.learningState?.lifecycle, .new)
        XCTAssertEqual(card.stack?.id, stack.id)

        card.learningState?.repeatCount = 2
        card.learningState?.lifecycle = .learning
        try harness.save()

        var edit = CardDraft(card: card)
        edit.word = "café noir"
        edit.stackID = other.id
        switch harness.library.saveCard(draft: edit, existing: card) {
        case .success(let edited):
            XCTAssertEqual(edited.word, "café noir")
            XCTAssertEqual(edited.learningState?.repeatCount, 2)
            XCTAssertEqual(edited.stack?.id, other.id)
        case .failure(let error):
            XCTFail("Edit failed: \(error)")
        }

        let fetched = try harness.context.fetch(FetchDescriptor<VocabularyCard>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].translation, "кофейня")
        XCTAssertEqual(fetched[0].tags.count, 2)

        switch harness.library.deleteCard(card) {
        case .success:
            XCTAssertTrue(try harness.context.fetch(FetchDescriptor<VocabularyCard>()).isEmpty)
        case .failure(let error):
            XCTFail("Delete failed: \(error)")
        }
    }

    func testDuplicateWarningCanBeOverriddenAndExposesExistingCard() throws {
        let stack = harness.makeStack()
        try harness.save()
        var draft = CardDraft()
        draft.word = "Ephemeral"
        draft.translation = "мимолетный"
        draft.stackID = stack.id
        XCTAssertEqual(try XCTUnwrap(harness.library.saveCard(draft: draft, existing: nil).get()).word, "Ephemeral")

        var duplicate = CardDraft()
        duplicate.word = "ephemeral"
        duplicate.translation = "мимолётный"
        duplicate.stackID = stack.id
        switch harness.library.saveCard(draft: duplicate, existing: nil) {
        case .failure(.duplicate(let id)):
            XCTAssertNotNil(harness.library.card(id: id))
        default:
            XCTFail("Expected duplicate warning")
        }

        duplicate.translation = "мимолетный"
        switch harness.library.saveCard(draft: duplicate, existing: nil, addAnyway: true) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Add anyway failed: \(error)")
        }
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<VocabularyCard>()).count, 2)
    }

    func testAppUsageAccumulatesPerDay() {
        harness.maintenance.addAppUsage(seconds: 120, at: harness.clock.now)
        harness.maintenance.addAppUsage(seconds: 30, at: harness.clock.now)
        let key = CalendarTools.dayKey(for: harness.clock.now, calendar: harness.calendar)
        XCTAssertEqual(harness.maintenance.appUsageByDay()[key] ?? 0, 150, accuracy: 0.01)
    }

    func testAppUsageIntervalSplitsAcrossMidnight() {
        let start = testDate("2026-11-06T23:50:00Z")
        let end = testDate("2026-11-07T00:10:00Z")
        harness.maintenance.addAppUsage(from: start, to: end)

        let usage = harness.maintenance.appUsageByDay()
        XCTAssertEqual(usage["2026-11-06"] ?? 0, 600, accuracy: 0.01)
        XCTAssertEqual(usage["2026-11-07"] ?? 0, 600, accuracy: 0.01)
    }

    func testAppUsageIntervalAccumulatesAcrossCalls() {
        let start = testDate("2026-11-07T09:00:00Z")
        let middle = testDate("2026-11-07T09:10:00Z")
        let end = testDate("2026-11-07T09:15:00Z")
        harness.maintenance.addAppUsage(from: start, to: middle)
        harness.maintenance.addAppUsage(from: middle, to: end)

        XCTAssertEqual(harness.maintenance.appUsageByDay()["2026-11-07"] ?? 0, 900, accuracy: 0.01)
    }

    func testAppUsageIntervalIgnoresEmptyAndNegativeRanges() {
        let now = testDate("2026-11-07T10:00:00Z")
        harness.maintenance.addAppUsage(from: now, to: now)
        harness.maintenance.addAppUsage(from: now, to: now.addingTimeInterval(-60))

        XCTAssertTrue(harness.maintenance.appUsageByDay().isEmpty)
    }

    func testAppUsageSecondsAtDateKeepsThatDaysAttribution() {
        let date = testDate("2026-11-07T23:59:00Z")
        harness.maintenance.addAppUsage(seconds: 120, at: date)

        let usage = harness.maintenance.appUsageByDay()
        XCTAssertEqual(usage["2026-11-07"] ?? 0, 120, accuracy: 0.01)
        XCTAssertNil(usage["2026-11-06"])
    }

    func testAppUsageSecondsEndingAfterMidnightSplitsAcrossDays() {
        harness.maintenance.addAppUsage(seconds: 120, at: testDate("2026-11-07T00:01:00Z"))

        let usage = harness.maintenance.appUsageByDay()
        XCTAssertEqual(usage["2026-11-06"] ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(usage["2026-11-07"] ?? 0, 60, accuracy: 0.01)
    }

    func testAppUsageIntervalUsesTheMaintenanceCalendarTimeZone() {
        let calendar = testCalendar(timeZone: "America/New_York")
        harness.maintenance.calendar = calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 30))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 0, minute: 30))!

        harness.maintenance.addAppUsage(from: start, to: end)

        let usage = harness.maintenance.appUsageByDay()
        XCTAssertEqual(usage["2026-11-07"] ?? 0, 1_800, accuracy: 0.01)
        XCTAssertEqual(usage["2026-11-08"] ?? 0, 1_800, accuracy: 0.01)
    }

    func testAppUsageIntervalOnDSTSpringForwardDayUsesTwentyThreeHours() {
        let calendar = testCalendar(timeZone: "America/New_York")
        harness.maintenance.calendar = calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 0))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        harness.maintenance.addAppUsage(from: start, to: end)

        XCTAssertEqual(harness.maintenance.appUsageByDay()["2026-03-08"] ?? 0, 23 * 3_600, accuracy: 0.01)
    }

    func testDuplicateInLibraryFindsTheSameWordInAnotherStack() throws {
        let first = harness.makeStack(name: "First")
        let second = harness.makeStack(name: "Second", isDefault: false)
        let existing = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: first)
        try harness.save()

        var draft = CardDraft()
        draft.word = "EPHEMERAL"
        draft.translation = "мимолетный"
        draft.stackID = second.id

        let duplicate = try XCTUnwrap(harness.library.duplicateInLibrary(of: draft))
        XCTAssertEqual(duplicate.id, existing.id)
        XCTAssertEqual(duplicate.stack?.name, "First")
    }

    func testEditingMetadataDoesNotWarnAboutDuplicatePairElsewhere() throws {
        let first = harness.makeStack(name: "First")
        let second = harness.makeStack(name: "Second", isDefault: false)
        let card = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: first)
        harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: second)
        try harness.save()

        var draft = CardDraft(card: card)
        draft.tagNames = ["B1"]
        draft.sourceExample = "An ephemeral feeling."
        XCTAssertFalse(harness.library.pairChanged(draft: draft, from: card))
        XCTAssertNil(harness.library.duplicateWarning(for: draft, existing: card))

        switch harness.library.saveCard(draft: draft, existing: card) {
        case .success(let saved):
            XCTAssertEqual(saved.tags.map(\.name), ["B1"])
            XCTAssertEqual(saved.sourceExample, "An ephemeral feeling.")
        case .failure(let error):
            XCTFail("Metadata edit failed: \(error)")
        }
    }

    func testPairComparisonIgnoresCaseAndWhitespace() throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: stack)
        try harness.save()

        var draft = CardDraft(card: card)
        draft.word = "  EPHEMERAL "
        draft.translation = "Мимолетный  "
        XCTAssertFalse(harness.library.pairChanged(draft: draft, from: card))
    }

    func testEditingPairStillWarnsAboutDuplicateElsewhere() throws {
        let first = harness.makeStack(name: "First")
        let second = harness.makeStack(name: "Second", isDefault: false)
        let card = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: first)
        let duplicate = harness.makeCard(word: "fleeting", translation: "мимолетный", stack: second)
        try harness.save()

        var draft = CardDraft(card: card)
        draft.word = "Fleeting"
        XCTAssertTrue(harness.library.pairChanged(draft: draft, from: card))
        XCTAssertEqual(harness.library.duplicateWarning(for: draft, existing: card)?.id, duplicate.id)
    }

    func testSaveCardSkipsStackDuplicateCheckWhenPairIsUnchanged() throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: stack)
        harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: stack)
        try harness.save()

        var draft = CardDraft(card: card)
        draft.tagNames = ["B1"]
        switch harness.library.saveCard(draft: draft, existing: card) {
        case .success(let saved):
            XCTAssertEqual(saved.tags.map(\.name), ["B1"])
        case .failure(let error):
            XCTFail("Metadata edit failed: \(error)")
        }
    }

    func testSaveCardStillChecksStackDuplicateWhenPairChanges() throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "ephemeral", translation: "мимолетный", stack: stack)
        let duplicate = harness.makeCard(word: "fleeting", translation: "мимолетный", stack: stack)
        try harness.save()

        var draft = CardDraft(card: card)
        draft.word = "fleeting"
        switch harness.library.saveCard(draft: draft, existing: card) {
        case .failure(.duplicate(let id)):
            XCTAssertEqual(id, duplicate.id)
        default:
            XCTFail("Expected duplicate warning")
        }
    }

    func testInvalidDraftDoesNotPersistAnything() throws {
        let stack = harness.makeStack()
        try harness.save()
        var draft = CardDraft()
        draft.word = "   "
        draft.translation = "   "
        draft.stackID = stack.id
        switch harness.library.saveCard(draft: draft, existing: nil) {
        case .failure(.invalid(let validation)):
            XCTAssertNotNil(validation.wordError)
            XCTAssertNotNil(validation.translationError)
        default:
            XCTFail("Expected validation failure")
        }
        XCTAssertTrue(try harness.context.fetch(FetchDescriptor<VocabularyCard>()).isEmpty)
    }

    func testStacksCanBeReorderedAndNewStacksAppearFirst() throws {
        let first = harness.makeStack(name: "First", isDefault: true)
        let second = harness.makeStack(name: "Second", isDefault: false)
        let third = harness.makeStack(name: "Third", isDefault: false)
        try harness.save()

        switch harness.library.reorderStacks([third.id, first.id, second.id]) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Reorder failed: \(error)")
        }
        XCTAssertEqual(harness.library.stacks().map(\.name), ["Third", "First", "Second"])

        switch harness.library.createStack(named: "New") {
        case .success:
            break
        case .failure(let error):
            XCTFail("Create failed: \(error)")
        }
        XCTAssertEqual(harness.library.stacks().map(\.name), ["New", "Third", "First", "Second"])
    }

    func testStackDeletionChoices() throws {
        let myWords = harness.makeStack(name: "My words", isDefault: true)
        let move = harness.makeStack(name: "Move", isDefault: false)
        let delete = harness.makeStack(name: "Delete", isDefault: false)
        let movedCard = harness.makeCard(word: "move-me", stack: move)
        let deletedCard = harness.makeCard(word: "delete-me", stack: delete)
        try harness.save()

        switch harness.library.deleteStack(move, mode: .moveCardsToDefault) {
        case .success:
            XCTAssertEqual(movedCard.stack?.id, myWords.id)
        case .failure(let error):
            XCTFail("Move delete failed: \(error)")
        }

        switch harness.library.deleteStack(delete, mode: .deleteCards) {
        case .success:
            XCTAssertNil(harness.library.card(id: deletedCard.id))
        case .failure(let error):
            XCTFail("Card delete failed: \(error)")
        }

        switch harness.library.deleteStack(myWords, mode: .deleteCards) {
        case .failure:
            break
        case .success:
            XCTFail("Default stack must not be deletable")
        }
    }

    func testTagsAreCaseInsensitivelyDeduplicated() throws {
        let stack = harness.makeStack()
        try harness.save()
        var draft = CardDraft()
        draft.word = "work"
        draft.translation = "работа"
        draft.stackID = stack.id
        draft.tagNames = ["Work", "WORK", "work"]
        _ = harness.library.saveCard(draft: draft, existing: nil)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<VocabularyTag>()).count, 1)
    }

    func testFileBackedStoreReopensWithUnicodeAndRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flipabulary-store-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.store")
        let configuration = ModelConfiguration(schema: FlipabularySchema.schema, url: url)
        var container: ModelContainer? = try ModelContainer(for: FlipabularySchema.schema, configurations: [configuration])
        let stackID = UUID()
        let cardID = UUID()
        do {
            let context = try XCTUnwrap(container?.mainContext)
            let stack = VocabularyStack(id: stackID, name: "Японский", isDefault: true)
            let tag = VocabularyTag(name: "旅行")
            context.insert(stack)
            context.insert(tag)
            let card = VocabularyCard(
                id: cardID,
                word: "旅行",
                translation: "путешествие",
                sourceExample: "旅行が好きです。",
                translatedExample: "Я люблю путешествовать.",
                stack: stack,
                tags: [tag]
            )
            context.insert(card)
            try context.save()
            container = nil
        }

        let reopened = try ModelContainer(for: FlipabularySchema.schema, configurations: [configuration])
        let cards = try reopened.mainContext.fetch(FetchDescriptor<VocabularyCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].id, cardID)
        XCTAssertEqual(cards[0].word, "旅行")
        XCTAssertEqual(cards[0].stack?.id, stackID)
        XCTAssertEqual(cards[0].tags.first?.name, "旅行")
        XCTAssertEqual(cards[0].learningState?.lifecycle, .new)
    }
}
