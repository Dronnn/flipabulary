import XCTest
import WidgetKit
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

    func testPerWidgetSourceSortAndTranslationsAreAlwaysUsed() {
        let snapshot = snapshot()
        let stackB = snapshot.stacks[1]
        let stackSource = WidgetSourceEntity(id: stackB.id.uuidString, name: "B", kind: .stack)
        let override = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            source: stackSource,
            sortOverride: .alphabetical,
            translationsOverride: true
        )
        XCTAssertEqual(override.stackID, stackB.id)
        XCTAssertNil(override.wordSetID)
        XCTAssertEqual(override.sort, .alphabetical)
        XCTAssertTrue(override.showTranslations)

        let all = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            source: .all,
            sortOverride: .recentlyAdded
        )
        XCTAssertNil(all.stackID)
        XCTAssertNil(all.wordSetID)
        XCTAssertEqual(all.summary.saved, 7)
        XCTAssertEqual(all.sort, .recentlyAdded)
        XCTAssertFalse(all.showTranslations)

        let appDefault = WidgetData.makeEntry(date: now, snapshot: snapshot)
        XCTAssertEqual(appDefault.stackID, snapshot.defaultStackID)
        XCTAssertEqual(appDefault.sort, .dueFirst)
        XCTAssertFalse(appDefault.showTranslations)
    }

    func testWordSetsProjectIndependentlyAndPreserveManualOrder() {
        var snapshot = snapshot()
        let stackA = snapshot.stacks[0]
        let stackB = snapshot.stacks[1]
        let late = stackA.cards.first(where: { $0.word == "late" })!
        let early = stackA.cards.first(where: { $0.word == "early" })!
        let secondStack = stackB.cards[0]
        let setA = WidgetWordSetSnapshot(
            id: UUID(),
            name: "Set A",
            cards: [late, early],
            savedCount: 2,
            dueCount: 2,
            learnedCount: 0,
            learningCount: 2,
            newCount: 0,
            nextDueAt: now.addingTimeInterval(10)
        )
        let setB = WidgetWordSetSnapshot(
            id: UUID(),
            name: "Set B",
            cards: [secondStack],
            savedCount: 1,
            dueCount: 1,
            learnedCount: 0,
            learningCount: 1,
            newCount: 0,
            nextDueAt: now
        )
        snapshot.wordSets = [setA, setB]
        snapshot.defaultWordSetID = setA.id

        let entityA = WidgetSourceEntity(id: setA.id.uuidString, name: setA.name, kind: .wordSet)
        let entityB = WidgetSourceEntity(id: setB.id.uuidString, name: setB.name, kind: .wordSet)

        let first = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            source: entityA,
            sortOverride: .manual
        )
        XCTAssertEqual(first.wordSetID, setA.id)
        XCTAssertEqual(first.scopeName, "Set A")
        XCTAssertEqual(first.cards.map(\.word), ["late", "early"])
        XCTAssertEqual(first.summary.saved, 2)

        let second = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            source: entityB,
            sortOverride: .manual
        )
        XCTAssertEqual(second.wordSetID, setB.id)
        XCTAssertEqual(second.scopeName, "Set B")
        XCTAssertEqual(second.cards.map(\.word), ["secondStack"])

        let defaults = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            sortOverride: .manual
        )
        XCTAssertEqual(defaults.wordSetID, setA.id)
        XCTAssertEqual(defaults.cards.map(\.word), ["late", "early"])
    }

    func testWordSetSnapshotStoreRoundTrip() throws {
        var snapshot = snapshot()
        let cards = snapshot.stacks[0].cards.prefix(2)
        let set = WidgetWordSetSnapshot(
            id: UUID(),
            name: "Custom",
            cards: Array(cards),
            savedCount: 2,
            dueCount: 1,
            learnedCount: 0,
            learningCount: 2,
            newCount: 0,
            nextDueAt: now
        )
        snapshot.wordSets = [set]
        snapshot.defaultWordSetID = set.id

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-set-store-\(UUID())")
        let store = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"), defaultsSuiteName: nil)
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        store.clear()
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
        let entity = WidgetSourceEntity(id: missingID.uuidString, name: "Gone", kind: .stack)
        let entry = WidgetData.makeEntry(
            date: now,
            snapshot: snapshot,
            source: entity
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

    func testHistoricalSchemaWithoutWordSetsOrLanguageLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-old-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("snapshot.json")
        let store = WidgetSnapshotStore(fileURL: url, defaultsSuiteName: nil)
        // Historical schema predates wordSets, defaultWordSetID, and languageCode.
        let historicalJSON = """
        {"schemaVersion":1,"generatedAt":"2026-11-07T10:00:00Z","stacks":[],"defaultSort":"dueFirst","defaultShowTranslations":false}
        """
        try Data(historicalJSON.utf8).write(to: url)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.generatedAt, now)
        XCTAssertEqual(loaded.wordSets, [])
        XCTAssertNil(loaded.defaultWordSetID)
        XCTAssertNil(loaded.languageCode)
        XCTAssertTrue(loaded.stacks.isEmpty)
    }
    func testTimelineProjectsDueLearnedDecayOnceAndRestoresNextDayNewQuota() throws {
        let due = now.addingTimeInterval(3600)
        let learned = WidgetCardSnapshot(id: UUID(), word: "learned", translation: "translation", lifecycle: "learned", repeatCount: 9, threshold: 9, dueAt: due, createdAt: now, decayPending: true)
        let mastered = WidgetCardSnapshot(id: UUID(), word: "mastered", translation: "translation", lifecycle: "learned", repeatCount: 9, threshold: 9, dueAt: nil, createdAt: now)
        let fresh = WidgetCardSnapshot(id: UUID(), word: "new", translation: "translation", lifecycle: "new", repeatCount: 0, threshold: 9, dueAt: nil, createdAt: now)
        var data = WidgetSnapshot.empty
        data.generatedAt = now
        let stack = WidgetStackSnapshot(id: UUID(), name: "stack", savedCount: 3, dueCount: 0, learnedCount: 2, learningCount: 0, newCount: 1, cards: [learned, mastered, fresh], nextDueAt: due, newCardsPerDay: 1, remainingNewCards: 0)
        data.stacks = [stack]
        data.wordSets = [WidgetWordSetSnapshot(id: UUID(), name: "set", cards: stack.cards, savedCount: 3, dueCount: 0, learnedCount: 2, learningCount: 0, newCount: 1, nextDueAt: due)]
        XCTAssertEqual(data.projected(at: now, calendar: testCalendar()).stacks[0].dueCount, 0)
        let atDue = data.projected(at: due, calendar: testCalendar())
        XCTAssertEqual(atDue.stacks[0].dueCount, 1)
        XCTAssertEqual(atDue.wordSets[0].dueCount, 1)
        XCTAssertEqual(atDue.stacks[0].cards[0].repeatCount, 8)
        XCTAssertEqual(atDue.projected(at: due, calendar: testCalendar()).stacks[0].cards[0].repeatCount, 8)
        XCTAssertEqual(atDue.summary(stackID: stack.id).nextCard?.id, learned.id)
        let tomorrow = data.projected(at: now.addingTimeInterval(86400), calendar: testCalendar())
        XCTAssertEqual(tomorrow.stacks[0].dueCount, 2)
        XCTAssertEqual(tomorrow.wordSets[0].dueCount, 2)
        XCTAssertEqual(tomorrow.stacks[0].cards[1].repeatCount, 9)
    }

    func testTimelineIncludesLaterCardDatesWithinTheSameStack() {
        let firstDue = now.addingTimeInterval(3600)
        let secondDue = now.addingTimeInterval(7200)
        let cards = [firstDue, secondDue].enumerated().map { index, due in
            WidgetCardSnapshot(id: UUID(), word: "word\(index)", translation: "translation", lifecycle: "learned", repeatCount: 9, threshold: 9, dueAt: due, createdAt: now, decayPending: true)
        }
        var data = WidgetSnapshot.empty
        data.generatedAt = now
        data.stacks = [WidgetStackSnapshot(id: UUID(), name: "stack", savedCount: 2, dueCount: 0, learnedCount: 2, learningCount: 0, newCount: 0, cards: cards, nextDueAt: firstDue)]
        let timeline = WidgetData.timeline(snapshot: data, now: now) { date in
            WidgetData.makeEntry(date: date, snapshot: data)
        }
        XCTAssertTrue(timeline.entries.contains { $0.date == firstDue && $0.summary.due == 1 })
        XCTAssertTrue(timeline.entries.contains { $0.date == secondDue && $0.summary.due == 2 })
        let laterTimeline = WidgetData.timeline(snapshot: data, now: firstDue.addingTimeInterval(1)) { date in
            WidgetData.makeEntry(date: date, snapshot: data)
        }
        XCTAssertTrue(laterTimeline.entries.contains { $0.date == secondDue && $0.summary.due == 2 })
    }

}
