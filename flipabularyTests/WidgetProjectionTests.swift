import XCTest
@testable import flipabulary

final class WidgetProjectionTests: XCTestCase {
    private let now = testDate("2026-11-07T10:00:00Z")

    private func card(_ word: String, due: Date?, created: Date, count: Int = 1, lifecycle: String = "learning") -> WidgetCardSnapshot {
        WidgetCardSnapshot(
            id: UUID(),
            word: word,
            translation: "t-\(word)",
            lifecycle: lifecycle,
            repeatCount: count,
            threshold: 5,
            dueAt: due,
            createdAt: created
        )
    }

    private func snapshot() -> WidgetSnapshot {
        let early = card("early", due: now.addingTimeInterval(-100), created: now.addingTimeInterval(-2_000))
        let late = card("late", due: now.addingTimeInterval(10), created: now.addingTimeInterval(-1_000))
        let sameDueEarlier = card("sameDueEarlier", due: now, created: now.addingTimeInterval(-500))
        let newCard = card("new", due: nil, created: now.addingTimeInterval(-100), count: 0, lifecycle: "new")
        let learned = card("learned", due: now.addingTimeInterval(86_400), created: now.addingTimeInterval(-4_000), count: 5, lifecycle: "learned")
        let stackA = WidgetStackSnapshot(
            id: UUID(),
            name: "A",
            savedCount: 5,
            dueCount: 3,
            learnedCount: 1,
            learningCount: 3,
            newCount: 1,
            cards: [early, late, sameDueEarlier, newCard, learned],
            nextDueAt: now
        )
        let stackB = WidgetStackSnapshot(
            id: UUID(),
            name: "B",
            savedCount: 2,
            dueCount: 1,
            learnedCount: 0,
            learningCount: 1,
            newCount: 1,
            cards: [card("secondStack", due: now, created: now)],
            nextDueAt: now
        )
        return WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: now,
            stacks: [stackA, stackB],
            defaultStackID: stackA.id,
            defaultSort: .dueFirst,
            defaultShowTranslations: false
        )
    }

    // MARK: UT-07

    func testDueFirstTieBreakersAndStableIDs() {
        let snapshot = snapshot()
        let stack = snapshot.stacks[0]
        let ordered = snapshot.projectedCards(stackID: stack.id, sort: .dueFirst)
        XCTAssertEqual(ordered.map(\.word), ["early", "sameDueEarlier", "late", "learned", "new"])
        XCTAssertEqual(snapshot.projectedCards(stackID: stack.id, sort: .dueFirst).map(\.id), ordered.map(\.id))
    }

    func testAlphabeticalAndRecentlyAddedSorts() {
        let snapshot = snapshot()
        let stack = snapshot.stacks[0]
        XCTAssertEqual(
            snapshot.projectedCards(stackID: stack.id, sort: .alphabetical).map(\.word),
            ["early", "late", "learned", "new", "sameDueEarlier"]
        )
        XCTAssertEqual(
            snapshot.projectedCards(stackID: stack.id, sort: .recentlyAdded).map(\.word),
            ["new", "sameDueEarlier", "late", "early", "learned"]
        )
    }

    func testListCapacitiesAreFixedAtThreeSixTenAndSixteen() {
        let cards = (0..<20).map { card("w\($0)", due: now, created: now.addingTimeInterval(TimeInterval($0))) }
        let stack = WidgetStackSnapshot(
            id: UUID(),
            name: "Many",
            savedCount: 20,
            dueCount: 20,
            learnedCount: 0,
            learningCount: 20,
            newCount: 0,
            cards: cards,
            nextDueAt: now
        )
        let snapshot = WidgetSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            stacks: [stack],
            defaultStackID: stack.id,
            defaultSort: .dueFirst,
            defaultShowTranslations: false
        )
        XCTAssertEqual(snapshot.listCards(stackID: stack.id, sort: .dueFirst, size: .small).count, 3)
        XCTAssertEqual(snapshot.listCards(stackID: stack.id, sort: .dueFirst, size: .medium).count, 6)
        XCTAssertEqual(snapshot.listCards(stackID: stack.id, sort: .dueFirst, size: .large).count, 10)
        XCTAssertEqual(snapshot.listCards(stackID: stack.id, sort: .dueFirst, size: .extraLarge).count, 16)
        XCTAssertEqual(WidgetSizeClass.small.entryCapacity, 3)
        XCTAssertEqual(WidgetSizeClass.medium.entryCapacity, 6)
        XCTAssertEqual(WidgetSizeClass.large.entryCapacity, 10)
        XCTAssertEqual(WidgetSizeClass.extraLarge.entryCapacity, 16)
    }

    func testAppDefaultsVersusPerInstanceOverrides() {
        let snapshot = snapshot()
        let stackB = snapshot.stacks[1]
        let entity = WidgetStackEntity(id: stackB.id.uuidString, name: "B", isAllStacks: false)
        let defaults = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            useAppDefaults: true,
            requestedStack: entity,
            sortOverride: .alphabetical,
            translationsOverride: true
        )
        XCTAssertEqual(defaults.stackID, stackB.id)
        XCTAssertEqual(defaults.sort, .dueFirst)
        XCTAssertFalse(defaults.showTranslations)

        let untouchedDefaults = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            useAppDefaults: true,
            requestedStack: nil
        )
        XCTAssertEqual(untouchedDefaults.stackID, snapshot.defaultStackID)
        XCTAssertEqual(untouchedDefaults.sort, .dueFirst)
        XCTAssertFalse(untouchedDefaults.showTranslations)

        let override = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            useAppDefaults: false,
            requestedStack: entity,
            sortOverride: .alphabetical,
            translationsOverride: true
        )
        XCTAssertEqual(override.stackID, stackB.id)
        XCTAssertEqual(override.sort, .alphabetical)
        XCTAssertTrue(override.showTranslations)
    }

    func testAllStacksAggregateAndSummary() {
        let snapshot = snapshot()
        let summary = snapshot.summary(stackID: nil)
        XCTAssertEqual(summary.saved, 7)
        XCTAssertEqual(summary.due, 4)
        XCTAssertEqual(summary.learning, 4)
        XCTAssertEqual(summary.learned, 1)
    }

    func testRemovedConfiguredStackFallsBack() {
        let snapshot = snapshot()
        let missingID = UUID()
        let entity = WidgetStackEntity(id: missingID.uuidString, name: "Gone", isAllStacks: false)
        let entry = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            useAppDefaults: false,
            requestedStack: entity
        )
        XCTAssertTrue(entry.missingConfiguredStack)
        XCTAssertEqual(entry.stackID, snapshot.defaultStackID)
        XCTAssertEqual(entry.scopeName, "A")
    }

    func testEmptySnapshotDoesNotInventVocabulary() {
        let empty = WidgetSnapshot.empty
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.projectedCards(stackID: nil, sort: .dueFirst).isEmpty)
        XCTAssertEqual(empty.summary(stackID: nil).saved, 0)
    }

    func testStoreRoundTripAndAtomicSnapshotRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-store-\(UUID())")
        let store = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"), defaultsSuiteName: nil)
        let snapshot = snapshot()
        try store.save(snapshot)
        let loaded = store.load()
        XCTAssertEqual(loaded, snapshot)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testStoreRejectsCorruptAndFutureSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-store-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.json")
        let store = WidgetSnapshotStore(fileURL: url, defaultsSuiteName: nil)
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(store.load())

        var future = snapshot()
        future.schemaVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(future).write(to: url)
        XCTAssertNil(store.load())
    }

    func testPreviousSchemaLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-store-\(UUID())")
        let store = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"), defaultsSuiteName: nil)
        var old = snapshot()
        old.schemaVersion = 0
        try store.save(old)
        XCTAssertEqual(store.load()?.schemaVersion, 0)
    }
}
