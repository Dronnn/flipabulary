import XCTest
import SwiftData
@testable import flipabulary

@MainActor
final class StatisticsFeatureTests: XCTestCase {
    private var harness: TestHarness!

    override func setUp() async throws {
        harness = try TestHarness()
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    private func session(stack: VocabularyStack, at date: Date) -> ReviewSession {
        let config = SessionConfig(
            stackID: stack.id,
            cardsPerSession: 20,
            newCardsPerDay: 10,
            shuffle: false,
            translationFirst: false,
            steps: LearningRules.defaultSteps,
            rules: .default,
            seed: 1
        )
        let queue = ReviewQueueEnvelope(
            presentations: [],
            admittedCardIDs: [],
            retryCounts: [:],
            nextRetryAt: nil
        )
        let session = ReviewSession(stackID: stack.id, startedAt: date, config: config, queue: queue)
        harness.context.insert(session)
        return session
    }

    private func event(
        card: VocabularyCard,
        session: ReviewSession,
        grade: ReviewGrade,
        at date: Date,
        front: Double,
        back: Double
    ) {
        let event = ReviewEvent(
            presentationID: UUID(),
            sessionID: session.id,
            cardID: card.id,
            grade: grade,
            timestamp: date,
            beforeRepeatCount: 0,
            afterRepeatCount: grade == .good ? 1 : 0,
            beforeLifecycle: .learning,
            afterLifecycle: .learning,
            rulesVersion: 1,
            card: card,
            frontSeconds: front,
            backSeconds: back
        )
        harness.context.insert(event)
    }

    func testWordStatisticsAggregatesSwipesAndFrontBackTime() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "stats", translation: "статистика", stack: stack)
        let session = session(stack: stack, at: harness.clock.now)
        event(card: card, session: session, grade: .good, at: harness.clock.now, front: 2, back: 3)
        event(card: card, session: session, grade: .again, at: harness.clock.now.addingTimeInterval(10), front: 4, back: 5)
        try harness.save()

        let statistics = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(statistics)
        XCTAssertEqual(stats.goodCount, 1)
        XCTAssertEqual(stats.againCount, 1)
        XCTAssertEqual(stats.totalGrades, 2)
        XCTAssertEqual(stats.frontSeconds, 6, accuracy: 0.01)
        XCTAssertEqual(stats.backSeconds, 8, accuracy: 0.01)
        XCTAssertEqual(stats.totalSeconds, 14, accuracy: 0.01)
        XCTAssertEqual(stats.history.count, 2)
        XCTAssertEqual(stats.history.first?.grade, .again)
    }

    func testLibraryStatisticsAggregatesTimeAnswersDaysAndStacks() async throws {
        let now = harness.clock.now
        let stackA = harness.makeStack(name: "A")
        let stackB = harness.makeStack(name: "B", isDefault: false)
        let cardA = harness.makeCard(word: "a", translation: "а", stack: stackA)
        let cardB = harness.makeCard(word: "b", translation: "б", stack: stackB)
        let sessionA = session(stack: stackA, at: now)
        sessionA.activeSeconds = 40
        let sessionB = session(stack: stackB, at: now.addingTimeInterval(-86_400))
        sessionB.activeSeconds = 20
        event(card: cardA, session: sessionA, grade: .good, at: now, front: 2, back: 3)
        event(card: cardA, session: sessionA, grade: .again, at: now, front: 1, back: 1)
        event(card: cardB, session: sessionB, grade: .good, at: now.addingTimeInterval(-86_400), front: 4, back: 6)
        harness.maintenance.addAppUsage(seconds: 60, at: now)
        try harness.save()

        let all = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppSeconds: 30
        )
        XCTAssertEqual(all.totalAppSeconds, 90, accuracy: 0.01)
        XCTAssertEqual(all.totalGood, 2)
        XCTAssertEqual(all.totalAgain, 1)
        XCTAssertEqual(all.totalReviews, 3)
        XCTAssertEqual(all.totalReviewSeconds, 17, accuracy: 0.01)
        XCTAssertEqual(all.days.count, 7)
        let today = CalendarTools.dayKey(for: now, calendar: harness.calendar)
        let todayPoint = try XCTUnwrap(all.days.first(where: { $0.dayKey == today }))
        XCTAssertEqual(todayPoint.good, 1)
        XCTAssertEqual(todayPoint.again, 1)
        XCTAssertEqual(todayPoint.reviewSeconds, 7, accuracy: 0.01)

        let first = try XCTUnwrap(all.stacks.first(where: { $0.id == stackA.id }))
        XCTAssertEqual(first.saved, 1)
        XCTAssertEqual(first.reviews, 2)
        XCTAssertEqual(first.reviewSeconds, 7, accuracy: 0.01)
        XCTAssertEqual(first.activeSessionSeconds, 40, accuracy: 0.01)

        let filtered = await harness.library.libraryStatistics(
            stackID: stackA.id,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppSeconds: 30
        )
        XCTAssertEqual(filtered.totalReviews, 2)
        XCTAssertEqual(filtered.totalReviewSeconds, 7, accuracy: 0.01)
        XCTAssertEqual(filtered.totalAppSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(filtered.stacks.count, 1)
        XCTAssertEqual(filtered.stacks.first?.id, stackA.id)
    }

    func testStatisticsIncludeEventsWhoseSessionIsMissing() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "orphan", stack: stack)
        let event = ReviewEvent(
            presentationID: UUID(),
            sessionID: UUID(),
            cardID: card.id,
            grade: .good,
            timestamp: harness.clock.now,
            beforeRepeatCount: 0,
            afterRepeatCount: 1,
            beforeLifecycle: .new,
            afterLifecycle: .learning,
            rulesVersion: 1,
            card: card,
            frontSeconds: 2,
            backSeconds: 4
        )
        harness.context.insert(event)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: harness.clock.now,
            calendar: harness.calendar,
            liveAppSeconds: 0
        )
        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalGood, 1)
        XCTAssertEqual(stats.totalReviewSeconds, 6, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first(where: { $0.id == stack.id })?.reviews, 1)
    }

    func testDifficultOverrideCanRemoveWordFromDifficult() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "difficult", translation: "трудный", stack: stack)
        let session = session(stack: stack, at: harness.clock.now)
        event(card: card, session: session, grade: .again, at: harness.clock.now, front: 1, back: 1)
        event(card: card, session: session, grade: .again, at: harness.clock.now.addingTimeInterval(1), front: 1, back: 1)
        try harness.save()

        let before = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        XCTAssertEqual(before?.isDifficult, true)

        guard case .success = harness.library.setDifficult(cardID: card.id, isDifficult: false) else {
            return XCTFail("Expected difficult override update")
        }
        let after = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        XCTAssertEqual(after?.isDifficult, false)

        let grades = (0..<2).map { _ in
            CardHistoryItem(grade: .again, timestamp: harness.clock.now)
        }
        let model = LibraryProjection.displayModel(
            card: card,
            stack: stack,
            rules: .default,
            recentGrades: grades
        )
        XCTAssertFalse(model.isDifficult)
    }

    func testFullyMasteredWordIsExcludedFromReviewQueue() throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "mastered", stack: stack)
        try harness.save()

        guard case .success = harness.library.setFullyLearned(cardID: card.id, mastered: true) else {
            return XCTFail("Expected mastery update")
        }
        guard case .empty = harness.review.requestReview(scopeID: stack.id) else {
            return XCTFail("Mastered word should not be admitted")
        }
    }

    func testWordStatisticsReflectsEditedStreak() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "streak", stack: stack)
        try harness.save()
        guard case .success = harness.library.setCorrectStreak(cardID: card.id, value: 5) else {
            return XCTFail("Expected streak update")
        }
        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)
        XCTAssertEqual(stats.repeatCount, 5)
        XCTAssertEqual(stats.lifecycle, .learned)
    }
}
