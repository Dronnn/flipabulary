import XCTest
import SwiftData
@testable import flipabulary

@MainActor
final class ReviewIntegrationTests: XCTestCase {
    private var harness: TestHarness!

    override func setUp() async throws {
        harness = try TestHarness()
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    private func dueCard(
        word: String,
        stack: VocabularyStack,
        count: Int = 1,
        createdAt: Date? = nil
    ) -> VocabularyCard {
        harness.makeCard(
            word: word,
            stack: stack,
            lifecycle: .learning,
            repeatCount: count,
            nextDueAt: harness.clock.now.addingTimeInterval(-10),
            createdAt: createdAt
        )
    }

    func testTimedReviewRecordsFrontAndBackSeconds() throws {
        let stack = harness.makeStack()
        let card = dueCard(word: "timed", stack: stack)
        let session = try start(stack)

        harness.clock.advance(by: 2)
        XCTAssertTrue(harness.review.reveal(session))
        harness.clock.advance(by: 3)
        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)

        let cardID = card.id
        let events = try harness.context.fetch(
            FetchDescriptor<ReviewEvent>(predicate: #Predicate { $0.cardID == cardID })
        )
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.frontSeconds ?? 0, 2, accuracy: 0.01)
        XCTAssertEqual(event.backSeconds ?? 0, 3, accuracy: 0.01)
    }

    func testManualMasteryCompletesEveryMilestoneAndCanBeUndone() throws {
        let stack = harness.makeStack()
        let card = dueCard(word: "mastered", stack: stack)

        guard case .success = harness.library.setFullyLearned(cardID: card.id, mastered: true) else {
            return XCTFail("Expected mastery update")
        }
        var state = try XCTUnwrap(card.learningState)
        XCTAssertEqual(state.lifecycle, .learned)
        XCTAssertEqual(state.appliedMilestones.count, LearningEngine.decayMilestones.count)
        XCTAssertNil(state.nextDueAt)

        guard case .success = harness.library.setFullyLearned(cardID: card.id, mastered: false) else {
            return XCTFail("Expected mastery undo")
        }
        state = try XCTUnwrap(card.learningState)
        XCTAssertEqual(state.lifecycle, .learning)
        XCTAssertTrue(state.appliedMilestones.isEmpty)
        XCTAssertNotNil(state.nextDueAt)
    }

    func testEditingStreakMovesBetweenLearningAndLearned() throws {
        let stack = harness.makeStack()
        let card = dueCard(word: "streak", stack: stack)

        guard case .success = harness.library.setCorrectStreak(cardID: card.id, value: 5) else {
            return XCTFail("Expected streak update")
        }
        XCTAssertEqual(card.learningState?.lifecycle, .learned)

        guard case .success = harness.library.setCorrectStreak(cardID: card.id, value: 2) else {
            return XCTFail("Expected streak update")
        }
        XCTAssertEqual(card.learningState?.lifecycle, .learning)
    }

    func testStackDirectionIsCapturedBySession() throws {
        let stack = harness.makeStack(translationFirst: false)
        stack.presentationMode = .backFirst
        try harness.save()
        _ = dueCard(word: "direction", stack: stack)

        let session = try start(stack)
        XCTAssertEqual(session.config?.effectivePresentationMode, .backFirst)
        let presentation = try XCTUnwrap(session.currentPresentation())
        XCTAssertEqual(presentation.translationFirst, true)
    }

    func testMixedDirectionCapturesAConcreteSidePerPresentation() throws {
        let stack = harness.makeStack(translationFirst: false)
        stack.presentationMode = .mixed
        try harness.save()
        _ = dueCard(word: "mixed", stack: stack)

        let session = try start(stack)
        XCTAssertEqual(session.config?.effectivePresentationMode, .mixed)
        let presentation = try XCTUnwrap(session.currentPresentation())
        XCTAssertNotNil(presentation.translationFirst)
    }

    private func start(_ stack: VocabularyStack) throws -> ReviewSession {
        switch harness.review.requestReview(scopeID: stack.id) {
        case .started(let id):
            return try XCTUnwrap(harness.review.session(id: id))
        case .existing(let id):
            return try XCTUnwrap(harness.review.session(id: id))
        case .failure(let message):
            XCTFail(message); throw NSError(domain: "test", code: 1)
        case .empty, .needsScope:
            XCTFail("Expected a session")
            throw NSError(domain: "test", code: 2)
        }
    }

    // MARK: IT-02

    func testStartRevealAndGradePersistOneConsistentTransaction() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let first = dueCard(word: "first", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-200))
        _ = dueCard(word: "second", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-100))
        try harness.save()

        let session = try start(stack)
        XCTAssertEqual(session.queue().admittedCardIDs.count, 2)
        XCTAssertEqual(Set(session.queue().presentations.map(\.cardID)).count, 2)
        XCTAssertEqual(session.config?.rules.correctThreshold, 5)

        let beforeCount = first.learningState?.repeatCount
        let eventsBefore = try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertEqual(first.learningState?.repeatCount, beforeCount)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, eventsBefore)
        XCTAssertTrue(session.revealed)

        guard let presentation = session.currentPresentation() else { return XCTFail("Missing presentation") }
        let result = harness.review.grade(session, grade: .good)
        XCTAssertEqual(result, .advanced)
        XCTAssertEqual(first.learningState?.repeatCount, 2)
        XCTAssertEqual(session.goodCount, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 1)
        XCTAssertFalse(session.revealed)
        XCTAssertTrue(session.committedPresentationIDs.contains(presentation.id))

        // Replaying the same presentation ID must not grade twice.
        session.currentPresentationID = presentation.id
        session.revealed = true
        session.showingBack = true
        XCTAssertEqual(harness.review.grade(session, grade: .good), .duplicate)
        XCTAssertEqual(first.learningState?.repeatCount, 2)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 1)
        XCTAssertEqual(session.goodCount, 1)
    }

    func testRatingRequiresReveal() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        _ = dueCard(word: "first", stack: stack)
        try harness.save()
        let session = try start(stack)
        if case .failure = harness.review.grade(session, grade: .good) {
            // Expected.
        } else {
            XCTFail("Expected a reveal guard")
        }
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 0)
    }

    func testLearnedReviewIsAdmittedAndAdvancesWithoutReturningToLearning() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let card = harness.makeCard(
            word: "learned",
            stack: stack,
            lifecycle: .learned,
            repeatCount: 5,
            nextDueAt: harness.clock.now.addingTimeInterval(-10)
        )
        try harness.save()
        let session = try start(stack)

        XCTAssertEqual(harness.review.currentCard(for: session)?.id, card.id)
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)
        XCTAssertEqual(card.learningState?.lifecycle, .learned)
        XCTAssertEqual(card.learningState?.repeatCount, 5)
        XCTAssertEqual(card.learningState?.appliedMilestones, [0])
        XCTAssertEqual(
            card.learningState?.nextDueAt,
            harness.clock.now.addingTimeInterval(3 * 86_400)
        )
    }

    func testSwipeRatingFromFrontDoesNotRequireReveal() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let card = dueCard(word: "front", stack: stack)
        try harness.save()
        let session = try start(stack)

        XCTAssertFalse(session.revealed)
        XCTAssertFalse(session.showingBack)
        XCTAssertEqual(harness.review.grade(session, grade: .good, allowUnrevealed: true), .completed)
        XCTAssertEqual(card.learningState?.repeatCount, 2)
        XCTAssertEqual(session.goodCount, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 1)
    }

    func testPersistenceFailureLeavesAnswerUnapplied() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let card = dueCard(word: "first", stack: stack)
        try harness.save()
        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        let originalCount = card.learningState?.repeatCount
        let originalLifecycle = card.learningState?.lifecycle

        harness.review.saveOverride = { throw NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "simulated failure"]) }
        let result = harness.review.grade(session, grade: .good)
        guard case .failure = result else { return XCTFail("Expected failure") }
        harness.review.saveOverride = nil

        let events = try harness.context.fetch(FetchDescriptor<ReviewEvent>())
        XCTAssertTrue(events.isEmpty)
        let fetched = try XCTUnwrap(harness.library.card(id: card.id))
        XCTAssertEqual(fetched.learningState?.repeatCount, originalCount)
        XCTAssertEqual(fetched.learningState?.lifecycle, originalLifecycle)
    }

    func testDailyNewQuotaAcrossSessionsAndNoConsumptionOnRevealOrAbandon() throws {
        let stack = harness.makeStack(newCardsPerDay: 1)
        harness.makeCard(word: "new-one", stack: stack)
        harness.makeCard(word: "new-two", stack: stack)
        try harness.save()

        let session = try start(stack)
        XCTAssertEqual(session.queue().admittedCardIDs.count, 1)
        let newCard = try XCTUnwrap(harness.review.currentCard(for: session))
        XCTAssertTrue(harness.review.reveal(session))

        // Abandoning/revealing does not consume the quota yet.
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 0)
        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 1)
        XCTAssertEqual(newCard.learningState?.lifecycle, .learning)

        switch harness.review.requestReview(scopeID: stack.id) {
        case .empty:
            break
        default:
            XCTFail("The daily new-card quota should stop a second new card")
        }
    }

    func testOpeningSessionDoesNotConsumeNewQuota() throws {
        let stack = harness.makeStack(newCardsPerDay: 1)
        harness.makeCard(word: "new-one", stack: stack)
        try harness.save()
        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 0)
        XCTAssertTrue(harness.review.endSession(session))
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 0)
    }

    func testAgainSchedulesBoundedRetries() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        _ = dueCard(word: "retry", stack: stack, count: 1)
        try harness.save()
        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))

        guard case .waiting = harness.review.grade(session, grade: .again) else {
            return XCTFail("Expected waiting for the first retry")
        }
        XCTAssertNil(session.currentPresentationID)
        XCTAssertEqual(session.queue().retryCounts.values.reduce(0, +), 1)

        for retry in 1...3 {
            harness.clock.advance(by: 61)
            XCTAssertTrue(harness.review.advanceIfPossible(session))
            XCTAssertTrue(harness.review.reveal(session))
            let result = harness.review.grade(session, grade: .again)
            if retry < 3 {
                guard case .waiting = result else { return XCTFail("Expected waiting on retry \(retry)") }
            } else {
                XCTAssertEqual(result, .completed)
            }
        }
        XCTAssertEqual(session.againCount, 4)
        XCTAssertEqual(session.queue().retryCounts.values.reduce(0, +), 3)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 4)
        XCTAssertEqual(session.status, .completed)
    }


    func testRepeatedFlipsPersistWithoutCreatingAnswerEventsAndGateRating() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        _ = dueCard(word: "flip", stack: stack)
        try harness.save()
        let session = try start(stack)
        let eventsBefore = try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count

        XCTAssertFalse(session.showingBack)
        XCTAssertFalse(session.revealed)
        if case .failure = harness.review.grade(session, grade: .good) {
            // Expected while the front is visible.
        } else {
            XCTFail("Rating must be unavailable on the front")
        }

        XCTAssertTrue(harness.review.setShowingBack(session, showing: true))
        XCTAssertTrue(session.revealed)
        XCTAssertTrue(session.showingBack)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, eventsBefore)

        for _ in 0..<4 {
            XCTAssertTrue(harness.review.setShowingBack(session, showing: false))
            XCTAssertTrue(session.revealed, "Flipping back must not forget that the answer was revealed")
            XCTAssertFalse(session.showingBack)
            if case .failure = harness.review.grade(session, grade: .again) {
                // Expected while the front is visible.
            } else {
                XCTFail("Rating must be unavailable on the front")
            }
            XCTAssertTrue(harness.review.setShowingBack(session, showing: true))
            XCTAssertTrue(session.showingBack)
        }
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, eventsBefore)

        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, eventsBefore + 1)
        XCTAssertFalse(session.showingBack)
        XCTAssertFalse(session.revealed)
    }

    // MARK: IT-03

    func testResumePreservesSideAndCapturedConfiguration() throws {
        let stack = harness.makeStack(cardsPerSession: 20, newCardsPerDay: 0, shuffle: false)
        _ = dueCard(word: "first", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-200))
        let second = dueCard(word: "second", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-100))
        try harness.save()

        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        _ = harness.review.grade(session, grade: .good)
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertTrue(session.revealed)
        XCTAssertEqual(harness.review.currentCard(for: session)?.id, second.id)

        stack.cardsPerSession = 3
        stack.shuffleOrder = true
        stack.customRules = LearningRules(
            correctThreshold: 2,
            resetOnMistake: false,
            autoDecrease: false,
            returnBelow: 1,
            steps: [30],
            version: 8
        )
        try harness.save()

        let resumedService = ReviewService(
            modelContext: harness.context,
            preferences: harness.preferences,
            library: harness.library,
            maintenance: harness.maintenance,
            clock: harness.clock,
            calendar: harness.calendar
        )
        let resumed = try XCTUnwrap(resumedService.latestActiveSession())
        XCTAssertEqual(resumed.id, session.id)
        XCTAssertEqual(resumed.config?.cardsPerSession, 20)
        XCTAssertEqual(resumed.config?.shuffle, false)
        XCTAssertEqual(resumed.config?.rules.correctThreshold, 5)
        XCTAssertTrue(resumed.revealed)
        XCTAssertEqual(resumedService.currentCard(for: resumed)?.id, second.id)
    }

    func testDeletedCurrentCardIsSkippedSafelyOnResume() throws {
        let stack = harness.makeStack(newCardsPerDay: 0, shuffle: false)
        let first = dueCard(word: "first", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-200))
        let second = dueCard(word: "second", stack: stack, createdAt: harness.clock.now.addingTimeInterval(-100))
        try harness.save()

        let session = try start(stack)
        let current = try XCTUnwrap(harness.review.currentCard(for: session))
        let remaining = current.id == first.id ? second : first
        XCTAssertTrue(harness.library.deleteCard(current).isSuccess)
        harness.review.repair(session)
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(harness.review.currentCard(for: session)?.id, remaining.id)
        XCTAssertNotNil(harness.review.currentPresentation(for: session))
    }

    func testDeletedStackEndsSessionWithoutCrash() throws {
        let defaultStack = harness.makeStack(name: "My words", isDefault: true)
        let stack = harness.makeStack(name: "Temporary", isDefault: false)
        _ = dueCard(word: "first", stack: stack)
        try harness.save()

        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        _ = harness.review.grade(session, grade: .good)
        _ = harness.library.deleteStack(stack, mode: .deleteCards)
        harness.review.repair(session)
        XCTAssertEqual(session.status, .completed)
        XCTAssertNotNil(harness.library.stack(id: defaultStack.id))
    }

    func testSingleCardReviewUsesSameRulesAndDoesNotDuplicateQuota() throws {
        let stack = harness.makeStack(newCardsPerDay: 1)
        let card = harness.makeCard(word: "single", stack: stack)
        try harness.save()

        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        XCTAssertEqual(harness.review.grade(session, grade: .good), .completed)
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 1)

        switch harness.review.requestReview(scopeID: nil, singleCardID: card.id) {
        case .started(let id):
            let single = try XCTUnwrap(harness.review.session(id: id))
            XCTAssertEqual(single.singleCardID, card.id)
            XCTAssertTrue(harness.review.reveal(single))
            _ = harness.review.grade(single, grade: .good)
            XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 1)
        case .failure(let message):
            XCTFail(message)
        default:
            XCTFail("Single-card review should start")
        }
    }

    func testDuplicateSessionOpenReturnsExistingSession() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        _ = dueCard(word: "first", stack: stack)
        try harness.save()
        let first = try start(stack)

        switch harness.review.requestReview(scopeID: stack.id) {
        case .existing(let id):
            XCTAssertEqual(id, first.id)
        default:
            XCTFail("Expected existing session")
        }
        XCTAssertEqual(harness.review.activeSessions().count, 1)
    }

    func testEndSessionPreservesCommittedAnswers() throws {
        let stack = harness.makeStack(newCardsPerDay: 0)
        _ = dueCard(word: "first", stack: stack)
        _ = dueCard(word: "second", stack: stack)
        try harness.save()
        let session = try start(stack)
        XCTAssertTrue(harness.review.reveal(session))
        _ = harness.review.grade(session, grade: .good)
        XCTAssertTrue(harness.review.reveal(session))
        let result = harness.review.endSession(session)
        XCTAssertTrue(result)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.goodCount, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ReviewEvent>()).count, 1)
        XCTAssertNil(harness.review.latestActiveSession())
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
