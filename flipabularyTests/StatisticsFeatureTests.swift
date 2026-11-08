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

        let liveUsage = AppUsageInterval(start: now.addingTimeInterval(-30), end: now)
        let all = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: liveUsage
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
            liveAppUsage: liveUsage
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
            liveAppUsage: nil
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


    // MARK: - Range filtering

    private func rangeStart(days: Int, now: Date) -> Date {
        let today = harness.calendar.startOfDay(for: now)
        return harness.calendar.date(byAdding: .day, value: -(days - 1), to: today)!
    }

    func testLibraryStatisticsFiltersReviewEventsOutsideTheSelectedRange() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "range", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-10 * 86_400), front: 100, back: 100)
        event(card: card, session: reviewSession, grade: .again, at: now, front: 2, back: 3)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalAgain, 1)
        XCTAssertEqual(stats.totalGood, 0)
        XCTAssertEqual(stats.totalReviewSeconds, 5, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.reviews, 1)
        XCTAssertEqual(stats.stacks.first?.reviewSeconds ?? 0, 5, accuracy: 0.01)
        let oldKey = CalendarTools.dayKey(for: now.addingTimeInterval(-10 * 86_400), calendar: harness.calendar)
        XCTAssertFalse(stats.days.contains { $0.dayKey == oldKey })
    }

    func testLibraryStatisticsIncludesEventAtExactRangeStart() async throws {
        let now = harness.clock.now
        let start = rangeStart(days: 7, now: now)
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "boundary", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: start, front: 3, back: 4)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalReviewSeconds, 7, accuracy: 0.01)
        let key = CalendarTools.dayKey(for: start, calendar: harness.calendar)
        XCTAssertEqual(stats.days.first { $0.dayKey == key }?.good, 1)
    }

    func testLibraryStatisticsExcludesEventOneSecondBeforeRangeStart() async throws {
        let now = harness.clock.now
        let start = rangeStart(days: 7, now: now)
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "before", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: start.addingTimeInterval(-1), front: 100, back: 100)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 0)
        XCTAssertEqual(stats.totalReviewSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.reviews, 0)
        XCTAssertFalse(stats.days.contains { $0.reviewSeconds > 0 })
    }

    func testLibraryStatisticsFiltersAppUsageOutsideTheSelectedRange() async throws {
        let now = harness.clock.now
        harness.maintenance.addAppUsage(seconds: 3_600, at: now.addingTimeInterval(-10 * 86_400))
        harness.maintenance.addAppUsage(seconds: 60, at: now)
        let live = AppUsageInterval(start: now.addingTimeInterval(-30), end: now)

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: live
        )

        XCTAssertEqual(stats.totalAppSeconds, 90, accuracy: 0.01)
        let todayKey = CalendarTools.dayKey(for: now, calendar: harness.calendar)
        XCTAssertEqual(stats.days.first { $0.dayKey == todayKey }?.appSeconds ?? 0, 90, accuracy: 0.01)
        let oldKey = CalendarTools.dayKey(for: now.addingTimeInterval(-10 * 86_400), calendar: harness.calendar)
        XCTAssertFalse(stats.days.contains { $0.dayKey == oldKey })
    }

    func testLibraryStatisticsSplitsLiveUsageAcrossMidnight() async throws {
        let liveEnd = testDate("2026-11-07T00:30:00Z")
        let liveStart = testDate("2026-11-06T23:30:00Z")

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: liveEnd,
            calendar: harness.calendar,
            liveAppUsage: AppUsageInterval(start: liveStart, end: liveEnd)
        )

        XCTAssertEqual(stats.totalAppSeconds, 3_600, accuracy: 0.01)
        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-06" }?.appSeconds ?? 0, 1_800, accuracy: 0.01)
        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-07" }?.appSeconds ?? 0, 1_800, accuracy: 0.01)
    }

    func testLibraryStatisticsSkipsLiveUsageOlderThanTheRange() async throws {
        let now = harness.clock.now
        let liveStart = now.addingTimeInterval(-10 * 86_400)

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: AppUsageInterval(start: liveStart, end: now)
        )

        let expected = now.timeIntervalSince(rangeStart(days: 7, now: now))
        XCTAssertEqual(stats.totalAppSeconds, expected, accuracy: 0.01)
        XCTAssertEqual(stats.days.count, 7)
    }

    func testLibraryStatisticsDoesNotAddLiveUsageToStackScope() async throws {
        let stack = harness.makeStack()
        let now = harness.clock.now
        let live = AppUsageInterval(start: now.addingTimeInterval(-30), end: now)

        let stats = await harness.library.libraryStatistics(
            stackID: stack.id,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: live
        )

        XCTAssertEqual(stats.totalAppSeconds, 0, accuracy: 0.01)
    }

    func testLibraryStatisticsClampsRangeDays() async throws {
        let now = harness.clock.now
        let one = await harness.library.libraryStatistics(
            stackID: nil, rangeDays: 0, now: now, calendar: harness.calendar, liveAppUsage: nil
        )
        let negative = await harness.library.libraryStatistics(
            stackID: nil, rangeDays: -10, now: now, calendar: harness.calendar, liveAppUsage: nil
        )
        let maximum = await harness.library.libraryStatistics(
            stackID: nil, rangeDays: 1_000, now: now, calendar: harness.calendar, liveAppUsage: nil
        )

        XCTAssertEqual(one.days.count, 1)
        XCTAssertEqual(negative.days.count, 1)
        XCTAssertEqual(maximum.days.count, 366)
    }

    func testLibraryStatisticsEmptyLibraryHasZeroTotalsAndNoNaN() async throws {
        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: harness.clock.now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertTrue(stats.stacks.isEmpty)
        XCTAssertEqual(stats.totalAppSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.totalReviewSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.totalReviews, 0)
        XCTAssertEqual(stats.totalGood, 0)
        XCTAssertEqual(stats.totalAgain, 0)
        XCTAssertEqual(stats.saved, 0)
        XCTAssertEqual(stats.learned, 0)
        XCTAssertEqual(stats.mastered, 0)
        XCTAssertEqual(stats.accuracy, 0, accuracy: 0.001)
        XCTAssertEqual(stats.days.count, 7)
        XCTAssertTrue(stats.days.allSatisfy { $0.appSeconds == 0 && $0.reviewSeconds == 0 && $0.reviews == 0 })
    }

    func testLibraryStatisticsFiltersSessionTimeByRange() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let recent = session(stack: stack, at: now.addingTimeInterval(-86_400))
        recent.activeSeconds = 40
        let old = session(stack: stack, at: now.addingTimeInterval(-10 * 86_400))
        old.activeSeconds = 20
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.stacks.first?.activeSessionSeconds ?? 0, 40, accuracy: 0.01)
    }

    func testLibraryStatisticsStackScopeFiltersReviewsAndSessionTime() async throws {
        let now = harness.clock.now
        let stackA = harness.makeStack(name: "A")
        let stackB = harness.makeStack(name: "B", isDefault: false)
        let cardA = harness.makeCard(word: "a", translation: "а", stack: stackA)
        let cardB = harness.makeCard(word: "b", translation: "б", stack: stackB)
        let sessionA = session(stack: stackA, at: now)
        sessionA.activeSeconds = 40
        let sessionB = session(stack: stackB, at: now)
        sessionB.activeSeconds = 20
        event(card: cardA, session: sessionA, grade: .good, at: now, front: 1, back: 2)
        event(card: cardB, session: sessionB, grade: .again, at: now, front: 3, back: 4)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: stackA.id,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalReviewSeconds, 3, accuracy: 0.01)
        XCTAssertEqual(stats.totalAppSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.count, 1)
        XCTAssertEqual(stats.stacks.first?.id, stackA.id)
        XCTAssertEqual(stats.stacks.first?.activeSessionSeconds ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.saved, 1)
    }

    func testLibraryStatisticsIncludesOrphanEventWithoutCardOnlyInGlobalTotals() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        _ = harness.makeCard(word: "existing", stack: stack)
        let event = ReviewEvent(
            presentationID: UUID(),
            sessionID: UUID(),
            cardID: UUID(),
            grade: .good,
            timestamp: now,
            beforeRepeatCount: 0,
            afterRepeatCount: 1,
            beforeLifecycle: .new,
            afterLifecycle: .learning,
            rulesVersion: 1,
            card: nil,
            frontSeconds: 2,
            backSeconds: 4
        )
        harness.context.insert(event)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalReviewSeconds, 6, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.reviews, 0)
        let key = CalendarTools.dayKey(for: now, calendar: harness.calendar)
        XCTAssertEqual(stats.days.first { $0.dayKey == key }?.good, 1)
    }

    func testLibraryStatisticsLastReviewedAtUsesNewestEventInRange() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "last", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        let newest = now.addingTimeInterval(-86_400)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-2 * 86_400), front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: newest, front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-10 * 86_400), front: 1, back: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        let stackStats = try XCTUnwrap(stats.stacks.first)
        XCTAssertEqual(stackStats.lastReviewedAt?.timeIntervalSince1970 ?? 0, newest.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLibraryStatisticsDayKeysUseProvidedCalendarTimeZone() async throws {
        let calendar = testCalendar(timeZone: "America/New_York")
        let now = testDate("2026-11-07T10:00:00Z")
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "tz", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        let lateEvent = testDate("2026-11-07T03:00:00Z")
        event(card: card, session: reviewSession, grade: .good, at: lateEvent, front: 1, back: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-06" }?.good, 1)
        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-07" }?.good, 0)
    }

    func testLibraryStatisticsEventAtMidnightBelongsToNewDay() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "midnight", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: testDate("2026-11-07T00:00:00Z"), front: 1, back: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-07" }?.good, 1)
        XCTAssertEqual(stats.days.first { $0.dayKey == "2026-11-06" }?.good, 0)
    }

    func testLibraryStatisticsCountsCurrentLearnedAndMasteredRegardlessOfRange() async throws {
        let stack = harness.makeStack()
        let mastered = harness.makeCard(word: "mastered", stack: stack, lifecycle: .learned, repeatCount: 5)
        mastered.learningState?.appliedMilestones = Set(LearningEngine.decayMilestones.map(\.index))
        mastered.learningState?.nextDueAt = nil
        _ = harness.makeCard(word: "learning", stack: stack, lifecycle: .learning, repeatCount: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: harness.clock.now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.saved, 2)
        XCTAssertEqual(stats.learned, 1)
        XCTAssertEqual(stats.mastered, 1)
        XCTAssertEqual(stats.stacks.first?.saved, 2)
        XCTAssertEqual(stats.stacks.first?.learned, 1)
        XCTAssertEqual(stats.stacks.first?.mastered, 1)
    }

    func testLibraryStatisticsAddsAppUsageToDaysWithoutReviews() async throws {
        let now = harness.clock.now
        let usageDate = now.addingTimeInterval(-2 * 86_400)
        harness.maintenance.addAppUsage(seconds: 120, at: usageDate)

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        let key = CalendarTools.dayKey(for: usageDate, calendar: harness.calendar)
        let day = stats.days.first { $0.dayKey == key }
        XCTAssertEqual(day?.appSeconds ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(day?.reviews, 0)
        XCTAssertEqual(stats.totalAppSeconds, 120, accuracy: 0.01)
    }

    func testLibraryStatisticsIgnoresNegativeAppUsageRecords() async throws {
        let now = harness.clock.now
        let todayKey = CalendarTools.dayKey(for: now, calendar: harness.calendar)
        let yesterdayKey = CalendarTools.dayKey(for: now.addingTimeInterval(-86_400), calendar: harness.calendar)
        harness.context.insert(AppUsageRecord(dayKey: todayKey, seconds: -100))
        harness.context.insert(AppUsageRecord(dayKey: yesterdayKey, seconds: 50))
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalAppSeconds, 50, accuracy: 0.01)
    }

    func testLibraryStatisticsIncludesEventAtNowAndExcludesFutureEvent() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "future", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now, front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: now.addingTimeInterval(3_600), front: 2, back: 2)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalGood, 1)
        XCTAssertEqual(stats.totalAgain, 0)
        XCTAssertEqual(stats.totalReviewSeconds, 2, accuracy: 0.01)
    }

    func testLibraryStatisticsRangeOneIncludesOnlyToday() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "one-day", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now, front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: now.addingTimeInterval(-86_400), front: 1, back: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 1,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.days.count, 1)
        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.totalGood, 1)
    }

    func testLibraryStatisticsRangeNinetyIncludesEightyNineDaysBack() async throws {
        let now = harness.clock.now
        let start = rangeStart(days: 90, now: now)
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "ninety", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: start, front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: start.addingTimeInterval(-1), front: 1, back: 1)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 90,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.days.count, 90)
        XCTAssertEqual(stats.totalReviews, 1)
    }

    func testLibraryStatisticsSumsFrontAndBackSecondsPerStack() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "faces", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now, front: 2, back: 3)
        event(card: card, session: reviewSession, grade: .again, at: now, front: 4, back: 5)
        try harness.save()

        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: nil
        )

        XCTAssertEqual(stats.totalReviewSeconds, 14, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.reviewSeconds ?? 0, 14, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.frontSeconds ?? 0, 6, accuracy: 0.01)
        XCTAssertEqual(stats.stacks.first?.backSeconds ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(stats.accuracy, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.stacks.first?.accuracy ?? 0, 0.5, accuracy: 0.001)
    }

    // MARK: - Word statistics

    func testWordStatisticsReturnsZeroesWithoutEvents() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "empty", stack: stack)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.totalGrades, 0)
        XCTAssertEqual(stats.timedGrades, 0)
        XCTAssertEqual(stats.goodCount, 0)
        XCTAssertEqual(stats.againCount, 0)
        XCTAssertEqual(stats.frontSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.backSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.totalSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.averageSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.accuracy, 0, accuracy: 0.001)
        XCTAssertNil(stats.lastReviewedAt)
        XCTAssertFalse(stats.isFullyMastered)
        XCTAssertFalse(stats.isDifficult)
        XCTAssertTrue(stats.history.isEmpty)
    }

    func testWordStatisticsLimitsHistoryToTwelveNewestEvents() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "history", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        for index in 0..<15 {
            event(
                card: card,
                session: reviewSession,
                grade: index.isMultiple(of: 2) ? .good : .again,
                at: now.addingTimeInterval(-Double(index)),
                front: 1,
                back: 1
            )
        }
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.history.count, 12)
        XCTAssertEqual(stats.history.first?.date.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(
            stats.history.last?.date.timeIntervalSince1970 ?? 0,
            now.addingTimeInterval(-11).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testWordStatisticsCountsOnlyTimedGradesForAverage() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "timed", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-2), front: 0, back: 0)
        event(card: card, session: reviewSession, grade: .again, at: now.addingTimeInterval(-1), front: 2, back: 3)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.totalGrades, 2)
        XCTAssertEqual(stats.timedGrades, 1)
        XCTAssertEqual(stats.totalSeconds, 5, accuracy: 0.01)
        XCTAssertEqual(stats.averageSeconds, 5, accuracy: 0.01)
    }

    func testWordStatisticsAccuracyUsesAllGrades() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "accuracy", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-3), front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-2), front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: now.addingTimeInterval(-1), front: 1, back: 1)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.accuracy, 2.0 / 3.0, accuracy: 0.001)
    }

    func testWordStatisticsAutomaticDifficultyUsesLastFiveGrades() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "difficult", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        let grades: [ReviewGrade] = [.again, .good, .again, .good, .good, .good]
        for (index, grade) in grades.enumerated() {
            event(
                card: card,
                session: reviewSession,
                grade: grade,
                at: now.addingTimeInterval(-Double(index)),
                front: 1,
                back: 1
            )
        }
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertTrue(stats.isDifficult)
    }

    func testWordStatisticsIgnoresAgainGradesOlderThanTheLastFive() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "not-difficult", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        let grades: [ReviewGrade] = [.good, .good, .good, .good, .again, .again]
        for (index, grade) in grades.enumerated() {
            event(
                card: card,
                session: reviewSession,
                grade: grade,
                at: now.addingTimeInterval(-Double(index)),
                front: 1,
                back: 1
            )
        }
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertFalse(stats.isDifficult)
    }

    func testWordStatisticsDifficultOverrideWins() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let forced = harness.makeCard(word: "forced", stack: stack)
        forced.difficultOverride = true
        let cleared = harness.makeCard(word: "cleared", stack: stack)
        cleared.difficultOverride = false
        let reviewSession = session(stack: stack, at: now)
        event(card: cleared, session: reviewSession, grade: .again, at: now.addingTimeInterval(-1), front: 1, back: 1)
        event(card: cleared, session: reviewSession, grade: .again, at: now, front: 1, back: 1)
        try harness.save()

        let forcedLoaded = await harness.library.wordStatistics(
            cardID: forced.id,
            now: now,
            calendar: harness.calendar
        )
        let clearedLoaded = await harness.library.wordStatistics(
            cardID: cleared.id,
            now: now,
            calendar: harness.calendar
        )

        XCTAssertEqual(forcedLoaded?.isDifficult, true)
        XCTAssertEqual(clearedLoaded?.isDifficult, false)
    }

    func testWordStatisticsMarksFullyMasteredOnlyWhenAllMilestonesApplied() async throws {
        let stack = harness.makeStack()
        let mastered = harness.makeCard(word: "mastered", stack: stack, lifecycle: .learned, repeatCount: 5)
        mastered.learningState?.appliedMilestones = Set(LearningEngine.decayMilestones.map(\.index))
        mastered.learningState?.nextDueAt = nil
        let learned = harness.makeCard(word: "learned", stack: stack, lifecycle: .learned, repeatCount: 5)
        learned.learningState?.appliedMilestones = [0]
        learned.learningState?.nextDueAt = harness.clock.now
        try harness.save()

        let masteredLoaded = await harness.library.wordStatistics(
            cardID: mastered.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let learnedLoaded = await harness.library.wordStatistics(
            cardID: learned.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )

        XCTAssertEqual(masteredLoaded?.isFullyMastered, true)
        XCTAssertEqual(learnedLoaded?.isFullyMastered, false)
    }

    func testWordStatisticsUsesStackRulesForThreshold() async throws {
        let stack = harness.makeStack()
        stack.customRules = LearningRules(
            correctThreshold: 7,
            resetOnMistake: false,
            autoDecrease: false,
            returnBelow: 3,
            steps: [30, 60],
            version: 2
        )
        let card = harness.makeCard(word: "threshold", stack: stack)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.threshold, 7)
    }

    func testWordStatisticsTreatsMissingTimingAsZero() async throws {
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "untimed", stack: stack)
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
            frontSeconds: nil,
            backSeconds: nil
        )
        harness.context.insert(event)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: harness.clock.now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.frontSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.backSeconds, 0, accuracy: 0.01)
        XCTAssertEqual(stats.timedGrades, 0)
    }

    func testWordStatisticsReturnsNilForMissingCard() async throws {
        let loaded = await harness.library.wordStatistics(
            cardID: UUID(),
            now: harness.clock.now,
            calendar: harness.calendar
        )
        XCTAssertNil(loaded)
    }

    func testWordStatisticsLastReviewedAtIsNewestEvent() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "last", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        let newest = now.addingTimeInterval(-86_400)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-2 * 86_400), front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .again, at: newest, front: 1, back: 1)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-3 * 86_400), front: 1, back: 1)
        try harness.save()

        let loaded = await harness.library.wordStatistics(
            cardID: card.id,
            now: now,
            calendar: harness.calendar
        )
        let stats = try XCTUnwrap(loaded)

        XCTAssertEqual(stats.lastReviewedAt?.timeIntervalSince1970 ?? 0, newest.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLibraryStatisticsSummaryMatchesDayChartTotals() async throws {
        let now = harness.clock.now
        let stack = harness.makeStack()
        let card = harness.makeCard(word: "invariant", stack: stack)
        let reviewSession = session(stack: stack, at: now)
        harness.maintenance.addAppUsage(seconds: 120, at: now.addingTimeInterval(-2 * 86_400))
        harness.maintenance.addAppUsage(seconds: 60, at: now)
        event(card: card, session: reviewSession, grade: .good, at: now.addingTimeInterval(-86_400), front: 2, back: 3)
        event(card: card, session: reviewSession, grade: .again, at: now, front: 4, back: 5)
        try harness.save()

        let live = AppUsageInterval(start: now.addingTimeInterval(-30), end: now)
        let stats = await harness.library.libraryStatistics(
            stackID: nil,
            rangeDays: 7,
            now: now,
            calendar: harness.calendar,
            liveAppUsage: live
        )

        XCTAssertEqual(stats.totalAppSeconds, stats.days.reduce(0) { $0 + $1.appSeconds }, accuracy: 0.01)
        XCTAssertEqual(stats.totalReviewSeconds, stats.days.reduce(0) { $0 + $1.reviewSeconds }, accuracy: 0.01)
        XCTAssertEqual(stats.totalReviews, stats.days.reduce(0) { $0 + $1.reviews })
        XCTAssertEqual(stats.totalGood, stats.days.reduce(0) { $0 + $1.good })
        XCTAssertEqual(stats.totalAgain, stats.days.reduce(0) { $0 + $1.again })
    }

    // MARK: - Duration formatting

    func testDurationFormattingTreatsZeroNegativeAndSubSecondAsOneSecond() {
        XCTAssertEqual(DurationFormatting.short(0), DurationFormatting.short(1))
        XCTAssertEqual(DurationFormatting.short(-10), DurationFormatting.short(1))
        XCTAssertEqual(DurationFormatting.short(0.4), DurationFormatting.short(1))
    }

    func testDurationFormattingProducesDistinctValuesForDifferentDurations() {
        let values = [60.0, 90.0, 3_600.0, 3_661.0, 86_400.0].map(DurationFormatting.short)
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertFalse(values.contains(""))
    }
}
