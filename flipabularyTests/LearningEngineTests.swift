import XCTest
@testable import flipabulary

final class LearningEngineTests: XCTestCase {
    private let calendar = testCalendar()
    private let start = testDate("2026-11-07T10:00:00Z")

    private func rules(
        threshold: Int = 5,
        reset: Bool = true,
        auto: Bool = true,
        returnBelow: Int = 5,
        steps: [TimeInterval] = [60, 600, 86_400]
    ) -> LearningRules {
        LearningRules(
            correctThreshold: threshold,
            resetOnMistake: reset,
            autoDecrease: auto,
            returnBelow: returnBelow,
            steps: steps,
            version: 1
        )
    }

    private func learning(count: Int, step: Int = 1, due: Date? = nil) -> LearningSnapshot {
        LearningSnapshot(
            repeatCount: count,
            lifecycle: .learning,
            stepIndex: step,
            nextDueAt: due ?? start,
            lastGradedAt: start.addingTimeInterval(-60),
            learnedAnchor: nil,
            appliedMilestones: [],
            mistakeReturn: false
        )
    }

    private func learned(count: Int = 5, anchor: Date? = nil, applied: Set<Int> = []) -> LearningSnapshot {
        LearningSnapshot(
            repeatCount: count,
            lifecycle: .learned,
            stepIndex: 0,
            nextDueAt: start.addingTimeInterval(86_400),
            lastGradedAt: start.addingTimeInterval(-60),
            learnedAnchor: anchor ?? start,
            appliedMilestones: applied,
            mistakeReturn: false
        )
    }

    // MARK: UT-02

    func testNewGoodLearningLearnedTransitionsAndThresholdExactly() {
        let first = LearningEngine.grade(.fresh, grade: .good, rules: rules(threshold: 3), at: start, calendar: calendar)
        XCTAssertEqual(first.after.lifecycle, .learning)
        XCTAssertEqual(first.after.repeatCount, 1)
        XCTAssertEqual(first.after.stepIndex, 1)
        XCTAssertEqual(first.after.nextDueAt, start.addingTimeInterval(60))

        let secondTime = start.addingTimeInterval(60)
        let second = LearningEngine.grade(first.after, grade: .good, rules: rules(threshold: 3), at: secondTime, calendar: calendar)
        XCTAssertEqual(second.after.repeatCount, 2)
        XCTAssertEqual(second.after.nextDueAt, secondTime.addingTimeInterval(600))

        let thirdTime = start.addingTimeInterval(660)
        let third = LearningEngine.grade(second.after, grade: .good, rules: rules(threshold: 3), at: thirdTime, calendar: calendar)
        XCTAssertTrue(third.becameLearned)
        XCTAssertEqual(third.after.lifecycle, .learned)
        XCTAssertEqual(third.after.repeatCount, 3)
        XCTAssertEqual(third.after.learnedAnchor, thirdTime)
        XCTAssertEqual(third.after.nextDueAt, thirdTime.addingTimeInterval(86_400))
    }

    func testNonDefaultThresholdAndCapping() {
        let state = learning(count: 1, step: 1)
        let transition = LearningEngine.grade(state, grade: .good, rules: rules(threshold: 2), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.repeatCount, 2)
    }

    func testAgainResetsWhenResetEnabled() {
        let state = learning(count: 4, step: 4)
        let transition = LearningEngine.grade(state, grade: .again, rules: rules(reset: true), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.repeatCount, 0)
        XCTAssertEqual(transition.after.lifecycle, .learning)
        XCTAssertEqual(transition.after.stepIndex, 0)
        XCTAssertEqual(transition.after.nextDueAt, start.addingTimeInterval(60))
        XCTAssertTrue(transition.after.mistakeReturn)
        XCTAssertFalse(transition.returnedFromLearned)
    }

    func testAgainRetainsCountWhenResetDisabled() {
        let state = learning(count: 4, step: 4)
        let transition = LearningEngine.grade(state, grade: .again, rules: rules(reset: false), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.repeatCount, 4)
        XCTAssertEqual(transition.after.lifecycle, .learning)
        XCTAssertTrue(transition.after.mistakeReturn)
    }

    func testLearnedMistakeReturnsToLearningAndGoodRegains() {
        let mistake = LearningEngine.grade(learned(count: 5), grade: .again, rules: rules(reset: false), at: start, calendar: calendar)
        XCTAssertTrue(mistake.returnedFromLearned)
        XCTAssertEqual(mistake.after.lifecycle, .learning)
        XCTAssertEqual(mistake.after.repeatCount, 5)
        XCTAssertTrue(mistake.after.mistakeReturn)

        let regained = LearningEngine.grade(mistake.after, grade: .good, rules: rules(reset: false), at: start.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(regained.after.lifecycle, .learned)
        XCTAssertFalse(regained.after.mistakeReturn)
        XCTAssertEqual(regained.after.repeatCount, 5)
    }

    func testGoodOnLearnedAdvancesToTheNextReviewInterval() {
        let state = learned(count: 5, anchor: start, applied: [0, 1])
        let transition = LearningEngine.grade(state, grade: .good, rules: rules(), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.repeatCount, 5)
        XCTAssertEqual(transition.after.appliedMilestones, [0, 1, 2])
        XCTAssertEqual(transition.after.learnedAnchor, start)
        XCTAssertEqual(
            transition.after.nextDueAt,
            calendar.date(byAdding: .day, value: 14, to: start)
        )
    }

    // MARK: UT-03

    func testCustomStepAdvancement() {
        let custom = rules(threshold: 5, steps: [30, 120, 3_000])
        var state = LearningSnapshot.fresh
        var time = start
        let expected: [TimeInterval] = [30, 120, 3_000, 3_000]
        for index in 0..<4 {
            let transition = LearningEngine.grade(state, grade: .good, rules: custom, at: time, calendar: calendar)
            state = transition.after
            XCTAssertEqual(state.nextDueAt, time.addingTimeInterval(expected[index]), "step \(index)")
            time = state.nextDueAt ?? time
        }
        XCTAssertEqual(state.lifecycle, .learning)
        XCTAssertEqual(state.repeatCount, 4)
    }

    func testDueBoundaries() {
        let due = start.addingTimeInterval(60)
        let state = learning(count: 1, due: due)
        XCTAssertFalse(LearningEngine.isDue(state, at: due.addingTimeInterval(-0.001)))
        XCTAssertTrue(LearningEngine.isDue(state, at: due))
        XCTAssertTrue(LearningEngine.isDue(state, at: due.addingTimeInterval(0.001)))
        XCTAssertFalse(LearningEngine.isDue(.fresh, at: start.addingTimeInterval(100_000)))
        XCTAssertTrue(LearningEngine.isDue(learned(), at: start.addingTimeInterval(100_000)))
        XCTAssertFalse(
            LearningEngine.isDue(
                learned(count: 5, applied: [0, 1, 2, 3, 4]),
                at: start.addingTimeInterval(100_000_000)
            )
        )
    }

    // MARK: UT-04

    func testLearnedReviewsCompleteAfterFiveGoodAnswers() {
        var state = learned(count: 5, anchor: start, applied: [])
        var reviewTime = state.nextDueAt!
        XCTAssertEqual(reviewTime, start.addingTimeInterval(86_400))
        let expected: [(review: Int, next: Int?)] = [
            (review: 0, next: 1),
            (review: 1, next: 2),
            (review: 2, next: 3),
            (review: 3, next: 4),
            (review: 4, next: nil)
        ]

        for step in expected {
            XCTAssertTrue(LearningEngine.isDue(state, at: reviewTime))
            let transition = LearningEngine.grade(state, grade: .good, rules: rules(), at: reviewTime, calendar: calendar)
            state = transition.after
            XCTAssertEqual(state.lifecycle, .learned)
            XCTAssertEqual(state.repeatCount, 5)
            XCTAssertTrue(state.appliedMilestones.contains(step.review))
            if let next = step.next {
                XCTAssertEqual(
                    state.nextDueAt,
                    LearningEngine.milestoneDate(index: next, anchor: reviewTime, calendar: calendar)
                )
                reviewTime = state.nextDueAt!
            } else {
                XCTAssertNil(state.nextDueAt)
            }
        }

        XCTAssertEqual(state.appliedMilestones, [0, 1, 2, 3, 4])
        XCTAssertFalse(LearningEngine.isDue(state, at: reviewTime.addingTimeInterval(86_400 * 365 * 10)))
    }

    func testMissedLearnedReviewStaysDueWithoutLosingRepeats() {
        let state = learned(count: 5, anchor: start, applied: [])
        let late = start.addingTimeInterval(86_400 * 10)
        let reconciled = LearningEngine.reconcileDecay(state, rules: rules(), at: late, calendar: calendar)
        XCTAssertEqual(reconciled.after, state)
        XCTAssertEqual(reconciled.after.repeatCount, 5)
        XCTAssertEqual(reconciled.after.appliedMilestones, [])
        XCTAssertTrue(LearningEngine.isDue(reconciled.after, at: late))
    }

    func testLearnedCardWithoutDueDateIsRepairedOnce() {
        var state = learned(count: 5, anchor: start, applied: [0, 1])
        state.nextDueAt = nil

        let repaired = LearningEngine.reconcileDecay(state, rules: rules(), at: start, calendar: calendar)
        XCTAssertEqual(
            repaired.after.nextDueAt,
            LearningEngine.milestoneDate(index: 0, anchor: start, calendar: calendar)
        )
        XCTAssertEqual(repaired.after.appliedMilestones, [0, 1])

        let again = LearningEngine.reconcileDecay(repaired.after, rules: rules(), at: start, calendar: calendar)
        XCTAssertEqual(again.after, repaired.after)
    }

    func testAgainOnLearnedReviewReturnsToLearning() {
        let state = learned(count: 5, anchor: start, applied: [0, 1])
        let transition = LearningEngine.grade(state, grade: .again, rules: rules(reset: false), at: start, calendar: calendar)
        XCTAssertTrue(transition.returnedFromLearned)
        XCTAssertEqual(transition.after.lifecycle, .learning)
        XCTAssertEqual(transition.after.repeatCount, 5)
        XCTAssertEqual(transition.after.appliedMilestones, [])
        XCTAssertNil(transition.after.learnedAnchor)
        XCTAssertEqual(transition.after.nextDueAt, start.addingTimeInterval(60))
        XCTAssertTrue(transition.after.mistakeReturn)
    }

    func testMasteredLearnedCardIsNotDue() {
        var state = learned(count: 5, anchor: start, applied: [0, 1, 2, 3, 4])
        state.nextDueAt = nil

        XCTAssertFalse(LearningEngine.isDue(state, at: start.addingTimeInterval(86_400 * 365 * 20)))

        let transition = LearningEngine.grade(state, grade: .good, rules: rules(), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertNil(transition.after.nextDueAt)
        XCTAssertEqual(transition.after.appliedMilestones, [0, 1, 2, 3, 4])
    }

    func testMonthEndAndLeapDayArithmetic() {
        var leapCalendar = testCalendar()
        leapCalendar.timeZone = TimeZone(identifier: "UTC")!
        let jan31 = testDate("2024-01-31T12:00:00Z")
        let monthEnd = LearningEngine.milestoneDate(index: 4, anchor: jan31, calendar: leapCalendar)
        XCTAssertEqual(monthEnd, testDate("2024-02-29T12:00:00Z"))

        let feb29 = testDate("2024-02-29T12:00:00Z")
        let nextDay = LearningEngine.milestoneDate(index: 0, anchor: feb29, calendar: leapCalendar)
        XCTAssertEqual(nextDay, testDate("2024-03-01T12:00:00Z"))
    }

    func testDSTDayArithmeticKeepsLocalWallTime() {
        var newYork = testCalendar(timeZone: "America/New_York")
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeDST = testDate("2025-03-08T17:00:00Z") // 12:00 EST
        let next = LearningEngine.milestoneDate(index: 0, anchor: beforeDST, calendar: newYork)!
        let components = newYork.dateComponents([.hour, .day, .month], from: next)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.day, 9)
    }

    func testInvalidRulesNormalizeToSafeValues() {
        let invalid = LearningRules(
            correctThreshold: 99,
            resetOnMistake: true,
            autoDecrease: true,
            returnBelow: 100,
            steps: [-1, 0, 0],
            version: 1
        ).normalized
        XCTAssertEqual(invalid.correctThreshold, 20)
        XCTAssertEqual(invalid.returnBelow, 20)
        XCTAssertEqual(invalid.steps, LearningRules.defaultSteps)
    }
}
