import XCTest
@testable import flipabulary

@MainActor
final class WidgetPublicationIntegrationTests: XCTestCase {
    private var harness: TestHarness!

    override func setUp() async throws {
        harness = try TestHarness()
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    func testCardChangesPublishSnapshotWithCountsAndProjection() throws {
        let stack = harness.makeStack(newCardsPerDay: 10)
        harness.prefer(stack)
        harness.makeCard(word: "due-one", stack: stack, lifecycle: .learning, repeatCount: 2, nextDueAt: harness.clock.now.addingTimeInterval(-10))
        harness.makeCard(word: "due-two", stack: stack, lifecycle: .learning, repeatCount: 1, nextDueAt: harness.clock.now.addingTimeInterval(-20))
        harness.makeCard(word: "new", stack: stack, lifecycle: .new, repeatCount: 0)
        try harness.save()

        harness.maintenance.publishSnapshot()
        let snapshot = try XCTUnwrap(harness.snapshotStore.load())
        XCTAssertEqual(snapshot.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.stacks.count, 1)
        XCTAssertEqual(snapshot.stacks[0].savedCount, 3)
        XCTAssertEqual(snapshot.stacks[0].dueCount, 3)
        XCTAssertEqual(snapshot.stacks[0].cards.count, 3)
        XCTAssertEqual(snapshot.defaultStackID, stack.id)

        let entry = WidgetData.makeEntry(date: harness.clock.now, snapshot: snapshot)
        XCTAssertEqual(entry.summary.saved, 3)
        XCTAssertEqual(entry.summary.due, 3)
        XCTAssertFalse(entry.missingConfiguredStack)
    }

    func testWordSetsPublishAcrossStacksInManualOrder() throws {
        let stackA = harness.makeStack(name: "A", newCardsPerDay: 0)
        let stackB = harness.makeStack(name: "B", isDefault: false, newCardsPerDay: 0)
        _ = harness.makeCard(word: "a1", stack: stackA)
        let b1 = harness.makeCard(word: "b1", stack: stackB)
        let a2 = harness.makeCard(word: "a2", stack: stackA)
        try harness.save()

        let set = WidgetWordSet(name: "Mix", cardIDs: [b1.id, a2.id])
        harness.preferences.preferences.widgetWordSets = [set]
        harness.preferences.preferences.widgetDefaults.wordSetID = set.id
        harness.preferences.preferences.widgetDefaults.sort = .manual
        harness.maintenance.publishSnapshot()

        let snapshot = try XCTUnwrap(harness.snapshotStore.load())
        XCTAssertEqual(snapshot.wordSets.count, 1)
        XCTAssertEqual(snapshot.wordSets[0].name, "Mix")
        XCTAssertEqual(snapshot.wordSets[0].cards.map(\.word), ["b1", "a2"])
        XCTAssertEqual(snapshot.defaultWordSetID, set.id)

        let entry = WidgetData.makeEntry(
            date: harness.clock.now,
            snapshot: snapshot,
            sortOverride: .manual
        )
        XCTAssertEqual(entry.wordSetID, set.id)
        XCTAssertEqual(entry.scopeName, "Mix")
        XCTAssertEqual(entry.cards.map(\.word), ["b1", "a2"])
        XCTAssertFalse(entry.missingConfiguredWordSet)
    }

    func testRatingAndDeletionRepublishSnapshot() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        harness.prefer(stack)
        harness.makeCard(word: "first", stack: stack, lifecycle: .learning, repeatCount: 1, nextDueAt: harness.clock.now.addingTimeInterval(-10))
        try harness.save()

        let session: ReviewSession
        switch harness.review.requestReview(scopeID: stack.id) {
        case .started(let id): session = try XCTUnwrap(harness.review.session(id: id))
        default:
            return XCTFail("Session should start")
        }
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)

        var snapshot = try XCTUnwrap(harness.snapshotStore.load())
        XCTAssertEqual(snapshot.stacks[0].dueCount, 0)
        XCTAssertEqual(snapshot.stacks[0].cards[0].repeatCount, 2)

        let card = try XCTUnwrap(harness.library.cards().first)
        _ = harness.library.deleteCard(card)
        snapshot = try XCTUnwrap(harness.snapshotStore.load())
        XCTAssertEqual(snapshot.stacks[0].cards.count, 0)
        XCTAssertEqual(snapshot.stacks[0].savedCount, 0)
    }

    func testSettingsChangePublishesDefaultScopeSortAndTranslations() throws {
        let stack = harness.makeStack()
        harness.prefer(stack)
        harness.makeCard(word: "first", stack: stack)
        try harness.save()

        var prefs = harness.preferences.preferences
        prefs.widgetDefaults.sort = .alphabetical
        prefs.widgetDefaults.showTranslations = true
        prefs.widgetDefaults.stackID = stack.id
        harness.preferences.preferences = prefs
        harness.maintenance.publishSnapshot()

        let snapshot = try XCTUnwrap(harness.snapshotStore.load())
        XCTAssertEqual(snapshot.defaultSort, .alphabetical)
        XCTAssertTrue(snapshot.defaultShowTranslations)
        XCTAssertEqual(snapshot.defaultStackID, stack.id)
    }

    func testIsolatedSnapshotStoreRoundTrip() throws {
        let snapshot = WidgetSnapshot.galleryPlaceholder
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-roundtrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"), defaultsSuiteName: nil)
        try store.save(snapshot)
        XCTAssertEqual(store.load()?.stacks.count, snapshot.stacks.count)
        XCTAssertEqual(store.load()?.schemaVersion, snapshot.schemaVersion)
    }

    func testRemovedScopeFallsBackInProjection() throws {
        let stack = harness.makeStack()
        harness.prefer(stack)
        harness.makeCard(word: "first", stack: stack)
        try harness.save()
        harness.maintenance.publishSnapshot()
        let snapshot = try XCTUnwrap(harness.snapshotStore.load())

        let missing = WidgetSourceEntity(id: UUID().uuidString, name: "Gone", kind: .stack)
        let entry = WidgetData.makeEntry(
            date: harness.clock.now,
            snapshot: snapshot,
            source: missing
        )
        XCTAssertTrue(entry.missingConfiguredStack)
        XCTAssertEqual(entry.stackID, stack.id)
    }
}
