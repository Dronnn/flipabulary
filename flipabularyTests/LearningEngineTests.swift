import XCTest
@testable import flipabulary

final class LearningEngineTests: XCTestCase {
    private let start = testDate("2026-11-07T10:00:00Z")
    private var calendar: Calendar { testCalendar() }

    private func good(_ state: LearningSnapshot, at date: Date, rules: LearningRules = .default) -> LearningSnapshot {
        LearningEngine.grade(state, grade: .good, rules: rules, at: date, calendar: calendar).after
    }

    private func graduate(rules: LearningRules = .default) throws -> LearningSnapshot {
        var state = good(.fresh, at: start, rules: rules)
        for (index, interval) in rules.steps.enumerated() {
            XCTAssertEqual(state.lifecycle, .learning)
            XCTAssertEqual(state.stepIndex, index)
            let previous = state.lastGradedAt ?? start
            let due = try XCTUnwrap(state.nextDueAt)
            XCTAssertEqual(due.timeIntervalSince(previous), interval, accuracy: 0.001)
            state = good(state, at: due, rules: rules)
        }
        XCTAssertEqual(state.lifecycle, .learned)
        XCTAssertEqual(state.reviewStageIndex, 0)
        XCTAssertEqual(state.repeatCount, rules.steps.count + 1)
        return state
    }

    func testEveryDefaultIntervalMustElapseBeforeLongTermReviews() throws {
        XCTAssertEqual(LearningRules.default.steps, [60, 300, 600, 1800, 3600, 10800, 43200, 86400])
        let state = try graduate()
        XCTAssertEqual(state.nextDueAt, calendar.date(byAdding: .day, value: 1, to: try XCTUnwrap(state.lastGradedAt)))
        XCTAssertFalse(state.isFullyMastered)
    }

    func testCustomLearningSequences() throws {
        for steps: [TimeInterval] in [[30], [60, 120, 3600], [86400, 172800]] {
            _ = try graduate(rules: LearningRules(steps: steps, version: 2))
        }
    }

    func testFullLongTermSequenceUsesPreviousAnswerAndCompletesOnlyAfterMonthlyGood() throws {
        var state = try graduate()
        for index in 0..<5 {
            let due = try XCTUnwrap(state.nextDueAt)
            XCTAssertEqual(state.reviewStageIndex, index)
            XCTAssertFalse(state.isFullyMastered)
            XCTAssertFalse(LearningEngine.isDue(state, at: due.addingTimeInterval(-0.001)))
            XCTAssertTrue(LearningEngine.isDue(state, at: due))
            let before = state.repeatCount
            let decayed = LearningEngine.reconcileDecay(state, rules: .default, at: due, calendar: calendar).after
            XCTAssertEqual(decayed.repeatCount, before - 1)
            XCTAssertEqual(decayed.nextDueAt, due)
            XCTAssertEqual(decayed.reviewStageIndex, index)
            XCTAssertEqual(LearningEngine.reconcileDecay(decayed, rules: .default, at: due, calendar: calendar).after, decayed)
            // Late answers schedule the next delay from the actual answer, not an old anchor.
            let answered = due.addingTimeInterval(7200)
            state = good(decayed, at: answered)
            XCTAssertEqual(state.reviewStageIndex, index + 1)
            XCTAssertEqual(state.repeatCount, before)
            XCTAssertEqual(state.nextDueAt, LearningEngine.milestoneDate(index: index + 1, anchor: answered, calendar: calendar))
        }
        XCTAssertTrue(state.isFullyMastered)
        XCTAssertNil(state.nextDueAt)
        XCTAssertFalse(LearningEngine.isDue(state, at: start.addingTimeInterval(86400 * 3650)))
    }

    func testAgainAtEveryShortAndLongStageRestartsFirstInterval() throws {
        var states: [LearningSnapshot] = [.fresh]
        var state = good(.fresh, at: start)
        for _ in LearningRules.default.steps {
            states.append(state)
            state = good(state, at: try XCTUnwrap(state.nextDueAt))
        }
        for _ in 0..<5 {
            states.append(state)
            state = good(state, at: try XCTUnwrap(state.nextDueAt))
        }
        states.append(state)
        for original in states {
            let at = original.nextDueAt ?? start
            let reset = LearningEngine.grade(original, grade: .again, rules: .default, at: at, calendar: calendar).after
            XCTAssertEqual(reset.lifecycle, .learning)
            XCTAssertEqual(reset.repeatCount, 0)
            XCTAssertEqual(reset.stepIndex, 0)
            XCTAssertEqual(reset.reviewStageIndex, 0)
            XCTAssertTrue(reset.appliedMilestones.isEmpty)
            XCTAssertNil(reset.learnedAnchor)
            XCTAssertEqual(reset.nextDueAt, at.addingTimeInterval(60))
            let next = good(reset, at: try XCTUnwrap(reset.nextDueAt))
            XCTAssertEqual(next.stepIndex, 1)
            XCTAssertEqual(next.nextDueAt, reset.nextDueAt?.addingTimeInterval(300))
        }
    }

    func testEarlyManualGoodDoesNotSkipShortLongOrCompletedStages() throws {
        var short = good(.fresh, at: start)
        let due = short.nextDueAt
        short = good(short, at: start.addingTimeInterval(1))
        XCTAssertEqual(short.stepIndex, 0)
        XCTAssertEqual(short.repeatCount, 1)
        XCTAssertEqual(short.nextDueAt, due)
        var long = try graduate()
        let previous = long
        long = good(long, at: try XCTUnwrap(long.nextDueAt).addingTimeInterval(-1))
        XCTAssertEqual(long.reviewStageIndex, previous.reviewStageIndex)
        XCTAssertEqual(long.repeatCount, previous.repeatCount)
        XCTAssertEqual(long.nextDueAt, previous.nextDueAt)
        long.reviewStageIndex = 5
        long.nextDueAt = nil
        let completed = good(long, at: start.addingTimeInterval(86400 * 365))
        XCTAssertTrue(completed.isFullyMastered)
        XCTAssertEqual(completed.repeatCount, long.repeatCount)
    }

    func testOverdueDecayDoesNotDependOnAppOpeningAndCannotSkipUnansweredStages() throws {
        let original = try graduate()
        let due = try XCTUnwrap(original.nextDueAt)
        let late = due.addingTimeInterval(86400 * 365)
        let atDue = LearningEngine.reconcileDecay(original, rules: .default, at: due, calendar: calendar).after
        let openedDaily = LearningEngine.reconcileDecay(atDue, rules: .default, at: late, calendar: calendar).after
        let openedLate = LearningEngine.reconcileDecay(original, rules: .default, at: late, calendar: calendar).after
        XCTAssertEqual(openedDaily, openedLate)
        XCTAssertEqual(openedLate.repeatCount, original.repeatCount - 1)
        XCTAssertEqual(openedLate.reviewStageIndex, 0)
        XCTAssertEqual(openedLate.nextDueAt, due)
        XCTAssertFalse(openedLate.isFullyMastered)
        XCTAssertEqual(good(openedLate, at: late).nextDueAt, calendar.date(byAdding: .day, value: 3, to: late))
    }

    func testGradeAppliesPendingDecayEvenWithoutMaintenance() throws {
        let state = try graduate()
        let after = good(state, at: try XCTUnwrap(state.nextDueAt))
        XCTAssertEqual(after.repeatCount, state.repeatCount)
        XCTAssertEqual(after.appliedMilestones, [0])
        XCTAssertEqual(after.reviewStageIndex, 1)
    }

    func testZeroCounterStillRequiresEveryLongReview() throws {
        var state = try graduate(rules: LearningRules(steps: [60], version: 1))
        state.repeatCount = 0
        let decayed = LearningEngine.reconcileDecay(state, rules: .default, at: try XCTUnwrap(state.nextDueAt)).after
        XCTAssertEqual(decayed.repeatCount, 0)
        XCTAssertFalse(decayed.isFullyMastered)
        XCTAssertEqual(good(decayed, at: try XCTUnwrap(decayed.nextDueAt)).reviewStageIndex, 1)
    }

    func testMonthEndLeapYearAndDSTUseCalendarDelays() throws {
        XCTAssertEqual(LearningEngine.milestoneDate(index: 4, anchor: testDate("2028-01-31T10:00:00Z"), calendar: calendar), testDate("2028-02-29T10:00:00Z"))
        XCTAssertEqual(LearningEngine.milestoneDate(index: 4, anchor: testDate("2027-01-31T10:00:00Z"), calendar: calendar), testDate("2027-02-28T10:00:00Z"))
        let local = testCalendar(timeZone: "America/New_York")
        let anchor = testDate("2026-03-07T15:00:00Z")
        XCTAssertEqual(LearningEngine.milestoneDate(index: 0, anchor: anchor, calendar: local), testDate("2026-03-08T14:00:00Z"))
        XCTAssertNil(LearningEngine.milestoneDate(index: 5, anchor: start, calendar: calendar))
    }

    func testInvalidIntervalsFallBackAndSessionUsesItsCapturedSteps() {
        for steps in [[], [0], [-1], [60, 60], [120, 60], [Double.infinity], [Double.nan]] {
            XCTAssertEqual(LearningRules(steps: steps, version: 1).normalized.steps, LearningRules.defaultSteps)
        }
    }
}
