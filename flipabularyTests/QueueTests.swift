import XCTest
@testable import flipabulary

final class QueueTests: XCTestCase {
    private let now = testDate("2026-11-07T10:00:00Z")

    private func candidate(
        _ id: UUID = UUID(),
        lifecycle: CardLifecycle,
        due: Date? = nil,
        created: Date? = nil
    ) -> LearningEngine.QueueCandidate {
        LearningEngine.QueueCandidate(
            id: id,
            lifecycle: lifecycle,
            nextDueAt: due,
            createdAt: created ?? now.addingTimeInterval(-1_000)
        )
    }

    func testDueLearningAndLearnedComeBeforeNewAndExcludeFutureAndMastered() {
        let dueA = UUID()
        let dueB = UUID()
        let future = UUID()
        let learned = UUID()
        let mastered = UUID()
        let new = UUID()
        let queue = LearningEngine.buildQueue(
            candidates: [
                candidate(new, lifecycle: .new),
                candidate(learned, lifecycle: .learned, due: now.addingTimeInterval(-50)),
                candidate(mastered, lifecycle: .learned),
                candidate(lifecycle: .learned, due: now.addingTimeInterval(50)),
                candidate(future, lifecycle: .learning, due: now.addingTimeInterval(10)),
                candidate(dueB, lifecycle: .learning, due: now.addingTimeInterval(-10)),
                candidate(dueA, lifecycle: .learning, due: now.addingTimeInterval(-100))
            ],
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertEqual(queue.admittedIDs, [dueA, learned, dueB, new])
        XCTAssertEqual(queue.learningCount, 3)
        XCTAssertEqual(queue.newCount, 1)
    }

    func testSessionCapLimitsAdmissionAndDailyQuotaIsShared() {
        let learning = (0..<2).map { _ in candidate(lifecycle: .learning, due: now.addingTimeInterval(-1)) }
        let new = (0..<5).map { _ in candidate(lifecycle: .new) }
        let first = LearningEngine.buildQueue(
            candidates: learning + new,
            cardsPerSession: 3,
            newCardsPerDay: 2,
            consumedNewCardIDs: [],
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertEqual(first.admittedIDs.count, 3)
        XCTAssertEqual(first.learningCount, 2)
        XCTAssertEqual(first.newCount, 1)

        let newIDs = Set(new.map(\.id))
        let consumedNew = Set(first.admittedIDs).intersection(newIDs)
        XCTAssertEqual(consumedNew.count, 1)
        let remaining = new.filter { !consumedNew.contains($0.id) }
        let second = LearningEngine.buildQueue(
            candidates: learning + remaining,
            cardsPerSession: 10,
            newCardsPerDay: 2,
            consumedNewCardIDs: consumedNew,
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertEqual(second.learningCount, 2)
        XCTAssertEqual(second.newCount, 1)
        XCTAssertEqual(second.admittedIDs.count, 3)
        XCTAssertTrue(Set(second.admittedIDs).isDisjoint(with: consumedNew))
    }

    func testDailyQuotaPreventsNewCardsAfterConsumption() {
        let new = [candidate(lifecycle: .new), candidate(lifecycle: .new), candidate(lifecycle: .new)]
        let queue = LearningEngine.buildQueue(
            candidates: new,
            cardsPerSession: 20,
            newCardsPerDay: 2,
            consumedNewCardIDs: [new[0].id, new[1].id],
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertEqual(queue.newCount, 0)
        XCTAssertTrue(queue.admittedIDs.isEmpty)
    }

    func testActionableDueCountIgnoresSessionCapButHonorsQuota() {
        let candidates = [
            candidate(lifecycle: .learning, due: now.addingTimeInterval(-1)),
            candidate(lifecycle: .learning, due: now.addingTimeInterval(-2))
        ] + (0..<10).map { _ in candidate(lifecycle: .new) }
        XCTAssertEqual(
            LearningEngine.actionableDueCount(candidates: candidates, newCardsPerDay: 3, consumedNewCardIDs: [], now: now),
            5
        )
        XCTAssertEqual(
            LearningEngine.actionableDueCount(candidates: candidates, newCardsPerDay: 3, consumedNewCardIDs: [candidates[2].id], now: now),
            4
        )
    }

    func testActionableDueCountIncludesDueLearnedAndExcludesMasteredAndFuture() {
        let candidates = [
            candidate(lifecycle: .learned, due: now.addingTimeInterval(-1)),
            candidate(lifecycle: .learned),
            candidate(lifecycle: .learned, due: now.addingTimeInterval(1)),
            candidate(lifecycle: .learning, due: now.addingTimeInterval(-2))
        ]
        XCTAssertEqual(
            LearningEngine.actionableDueCount(candidates: candidates, newCardsPerDay: 0, consumedNewCardIDs: [], now: now),
            2
        )
    }

    func testShuffleDeterminismAndUniqueIDs() {
        let candidates = (0..<12).map { index in
            candidate(lifecycle: index < 6 ? .learning : .new, due: index < 6 ? now.addingTimeInterval(-1) : nil)
        }
        let first = LearningEngine.buildQueue(
            candidates: candidates,
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: true,
            seed: 1234,
            now: now
        )
        let second = LearningEngine.buildQueue(
            candidates: candidates,
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: true,
            seed: 1234,
            now: now
        )
        let different = LearningEngine.buildQueue(
            candidates: candidates,
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: true,
            seed: 9999,
            now: now
        )
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.admittedIDs, different.admittedIDs)
        XCTAssertEqual(Set(first.admittedIDs).count, first.admittedIDs.count)
    }

    func testNonShuffleOrderingIsStableAndExcludesDuplicates() {
        let id1 = UUID()
        let id2 = UUID()
        let queue = LearningEngine.buildQueue(
            candidates: [
                candidate(id2, lifecycle: .learning, due: now.addingTimeInterval(-5), created: now.addingTimeInterval(-20)),
                candidate(id1, lifecycle: .learning, due: now.addingTimeInterval(-5), created: now.addingTimeInterval(-10))
            ],
            cardsPerSession: 10,
            newCardsPerDay: 0,
            consumedNewCardIDs: [],
            shuffle: false,
            seed: 0,
            now: now
        )
        XCTAssertEqual(queue.admittedIDs, [id2, id1])
        XCTAssertEqual(Set(queue.admittedIDs).count, queue.admittedIDs.count)
    }

    func testEmptyAndFutureOnlyQueues() {
        let empty = LearningEngine.buildQueue(
            candidates: [],
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertTrue(empty.admittedIDs.isEmpty)

        let future = LearningEngine.buildQueue(
            candidates: [candidate(lifecycle: .learning, due: now.addingTimeInterval(60))],
            cardsPerSession: 20,
            newCardsPerDay: 10,
            consumedNewCardIDs: [],
            shuffle: false,
            seed: 1,
            now: now
        )
        XCTAssertTrue(future.admittedIDs.isEmpty)
    }

    func testRetryDueUsesFirstStep() {
        let rules = LearningRules.default
        XCTAssertEqual(LearningEngine.retryDueAt(now: now, rules: rules), now.addingTimeInterval(60))
        XCTAssertEqual(LearningEngine.maximumRetryPresentations, 3)
    }
}
