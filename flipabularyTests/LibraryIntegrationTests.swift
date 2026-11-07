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
