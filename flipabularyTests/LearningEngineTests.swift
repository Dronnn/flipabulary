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

    func testGoodOnLearnedReinforcesAnchorWithoutLearningStep() {
        let state = learned(count: 5, anchor: start.addingTimeInterval(-86_400 * 3), applied: [0, 1])
        let transition = LearningEngine.grade(state, grade: .good, rules: rules(), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.repeatCount, 5)
        XCTAssertEqual(transition.after.learnedAnchor, start)
        XCTAssertEqual(transition.after.appliedMilestones, [])
        XCTAssertEqual(transition.after.nextDueAt, start.addingTimeInterval(86_400))
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
        XCTAssertFalse(LearningEngine.isDue(learned(), at: start.addingTimeInterval(100_000)))
        XCTAssertFalse(
            LearningEngine.isDue(
                learned(count: 5, applied: [0, 1, 2, 3, 4]),
                at: start.addingTimeInterval(100_000_000)
            )
        )
    }

    // MARK: UT-04

    func testEachMilestoneBoundarySubtractsExactlyOne() {
        let reviewRules = rules(threshold: 10, returnBelow: 1)
        var state = learned(count: 10, anchor: start)
        let expectedDays = [1, 3, 7, 14]

        for (index, days) in expectedDays.enumerated() {
            let boundary = calendar.date(byAdding: .day, value: days, to: start)!
            let justBefore = LearningEngine.reconcileDecay(
                state,
                rules: reviewRules,
                at: boundary.addingTimeInterval(-1),
                calendar: calendar
            )
            XCTAssertEqual(justBefore.after.repeatCount, 10 - index, "day \(days) just before")
            XCTAssertEqual(justBefore.after, state, "day \(days) just before")

            let reached = LearningEngine.reconcileDecay(state, rules: reviewRules, at: boundary, calendar: calendar)
            XCTAssertEqual(reached.after.repeatCount, 10 - index - 1, "day \(days)")
            XCTAssertEqual(reached.after.lifecycle, .learned, "day \(days)")
            XCTAssertEqual(reached.after.appliedMilestones, Set(0...index), "day \(days)")
            state = reached.after
        }

        let month = calendar.date(byAdding: .month, value: 1, to: start)!
        let justBeforeMonth = LearningEngine.reconcileDecay(
            state,
            rules: reviewRules,
            at: month.addingTimeInterval(-1),
            calendar: calendar
        )
        XCTAssertEqual(justBeforeMonth.after.repeatCount, 6)

        let monthReached = LearningEngine.reconcileDecay(state, rules: reviewRules, at: month, calendar: calendar)
        XCTAssertEqual(monthReached.after.repeatCount, 5)
        XCTAssertEqual(monthReached.after.appliedMilestones, [0, 1, 2, 3, 4])
        XCTAssertNil(monthReached.after.nextDueAt)
    }

    func testDefaultRulesReturnToLearningAfterFirstDay() {
        let afterOneDay = start.addingTimeInterval(86_400)
        let transition = LearningEngine.reconcileDecay(
            learned(count: 5, anchor: start),
            rules: rules(threshold: 5, returnBelow: 5),
            at: afterOneDay,
            calendar: calendar
        )
        XCTAssertEqual(transition.after.repeatCount, 4)
        XCTAssertEqual(transition.after.lifecycle, .learning)
        XCTAssertTrue(transition.returnedFromLearned)
        XCTAssertEqual(transition.after.nextDueAt, afterOneDay)
        XCTAssertEqual(transition.after.appliedMilestones, [0])
        XCTAssertTrue(transition.after.mistakeReturn)
    }

    func testReturnBelowIsStrictlyLowerBoundary() {
        let afterOneDay = start.addingTimeInterval(86_400)

        let equal = LearningEngine.reconcileDecay(
            learned(count: 5, anchor: start),
            rules: rules(threshold: 5, returnBelow: 4),
            at: afterOneDay,
            calendar: calendar
        )
        XCTAssertEqual(equal.after.repeatCount, 4)
        XCTAssertEqual(equal.after.lifecycle, .learned)
        XCTAssertFalse(equal.returnedFromLearned)

        let below = LearningEngine.reconcileDecay(
            learned(count: 5, anchor: start),
            rules: rules(threshold: 5, returnBelow: 5),
            at: afterOneDay,
            calendar: calendar
        )
        XCTAssertEqual(below.after.repeatCount, 4)
        XCTAssertEqual(below.after.lifecycle, .learning)
        XCTAssertTrue(below.returnedFromLearned)
    }

    func testEachMilestoneOnceWhileStayingLearned() {
        let state = learned(count: 5, anchor: start)
        let atTenDays = start.addingTimeInterval(10 * 86_400)
        let first = LearningEngine.reconcileDecay(state, rules: rules(returnBelow: 1), at: atTenDays, calendar: calendar)
        XCTAssertEqual(first.after.repeatCount, 2)
        XCTAssertEqual(first.after.lifecycle, .learned)
        XCTAssertEqual(first.after.appliedMilestones, [0, 1, 2])

        let second = LearningEngine.reconcileDecay(first.after, rules: rules(returnBelow: 1), at: atTenDays, calendar: calendar)
        XCTAssertEqual(second.after.repeatCount, 2)
        XCTAssertEqual(second.after.appliedMilestones, [0, 1, 2])
        XCTAssertEqual(second.after, first.after)
    }

    func testLongAbsenceAppliesAllReachedMilestonesEvenAfterReturning() {
        let state = learned(count: 5, anchor: start)
        let atTwoMonths = calendar.date(byAdding: .month, value: 2, to: start)!
        let transition = LearningEngine.reconcileDecay(state, rules: rules(returnBelow: 5), at: atTwoMonths, calendar: calendar)
        XCTAssertEqual(transition.after.repeatCount, 0)
        XCTAssertEqual(transition.after.appliedMilestones, [0, 1, 2, 3, 4])
        XCTAssertEqual(transition.after.lifecycle, .learning)
        XCTAssertTrue(transition.returnedFromLearned)
    }

    func testCountClampsAtZero() {
        let state = learned(count: 1, anchor: start)
        let atTwoMonths = calendar.date(byAdding: .month, value: 2, to: start)!
        let transition = LearningEngine.reconcileDecay(state, rules: rules(returnBelow: 1), at: atTwoMonths, calendar: calendar)
        XCTAssertEqual(transition.after.repeatCount, 0)
        XCTAssertGreaterThanOrEqual(transition.after.repeatCount, 0)
    }

    func testHysteresisAllowsLearnedWithFewerRepeatsThanThreshold() {
        let state = learned(count: 5, anchor: start)
        let transition = LearningEngine.reconcileDecay(
            state,
            rules: rules(threshold: 5, returnBelow: 3),
            at: start.addingTimeInterval(86_400),
            calendar: calendar
        )
        XCTAssertEqual(transition.after.repeatCount, 4)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertFalse(transition.returnedFromLearned)
    }

    func testAutoDecreaseOffPreservesProgressAndReanchorAvoidsRetroactiveLoss() {
        let state = learned(count: 5, anchor: start)
        let disabled = LearningEngine.reconcileDecay(
            state,
            rules: rules(auto: false),
            at: start.addingTimeInterval(86_400 * 40),
            calendar: calendar
        )
        XCTAssertEqual(disabled.after, state)
        XCTAssertEqual(disabled.after.repeatCount, 5)
        XCTAssertEqual(disabled.after.lifecycle, .learned)

        let enableTime = start.addingTimeInterval(86_400 * 40)
        let reanchored = LearningEngine.reanchorForEnabledDecay(state, at: enableTime, calendar: calendar)
        XCTAssertEqual(reanchored.learnedAnchor, enableTime)
        XCTAssertEqual(reanchored.appliedMilestones, [])
        XCTAssertEqual(reanchored.nextDueAt, enableTime.addingTimeInterval(86_400))

        let justBefore = LearningEngine.reconcileDecay(
            reanchored,
            rules: rules(),
            at: enableTime.addingTimeInterval(86_400 - 1),
            calendar: calendar
        )
        XCTAssertEqual(justBefore.after.repeatCount, 5)
        XCTAssertEqual(justBefore.after.lifecycle, .learned)
    }

    func testReanchorIgnoresNonLearnedCards() {
        let state = learning(count: 2)
        XCTAssertEqual(LearningEngine.reanchorForEnabledDecay(state, at: start, calendar: calendar), state)
    }

    func testNextReturnToLearningDateFollowsHysteresis() {
        let defaultRules = rules(threshold: 5, returnBelow: 5)
        XCTAssertEqual(
            LearningEngine.nextReturnToLearningDate(learned(count: 5), rules: defaultRules, after: start, calendar: calendar),
            start.addingTimeInterval(86_400)
        )

        let lowerReturn = rules(threshold: 5, returnBelow: 3)
        XCTAssertEqual(
            LearningEngine.nextReturnToLearningDate(learned(count: 5), rules: lowerReturn, after: start, calendar: calendar),
            start.addingTimeInterval(86_400 * 7)
        )

        let noReturn = rules(threshold: 10, returnBelow: 3)
        XCTAssertNil(
            LearningEngine.nextReturnToLearningDate(learned(count: 10), rules: noReturn, after: start, calendar: calendar)
        )
        XCTAssertNil(
            LearningEngine.nextReturnToLearningDate(learned(count: 5), rules: rules(auto: false), after: start, calendar: calendar)
        )
    }

    func testBackwardClockAppliesNothing() {
        let state = learned(count: 5, anchor: start)
        let transition = LearningEngine.reconcileDecay(
            state,
            rules: rules(),
            at: start.addingTimeInterval(-86_400 * 10),
            calendar: calendar
        )
        XCTAssertEqual(transition.after.repeatCount, 5)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.appliedMilestones, [])
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

    func testFullyDecayedLearnedCardIsNotDue() {
        var state = learned(count: 10, anchor: start, applied: [0, 1, 2, 3, 4])
        state.nextDueAt = nil

        XCTAssertFalse(LearningEngine.isDue(state, at: start.addingTimeInterval(86_400 * 365 * 20)))
        XCTAssertNil(
            LearningEngine.nextReturnToLearningDate(
                state,
                rules: rules(threshold: 10, returnBelow: 1),
                after: start,
                calendar: calendar
            )
        )
    }

    func testGoodOnFullyDecayedLearnedCardReanchorsTheSchedule() {
        var state = learned(count: 10, anchor: start, applied: [0, 1, 2, 3, 4])
        state.nextDueAt = nil

        let transition = LearningEngine.grade(state, grade: .good, rules: rules(threshold: 10, returnBelow: 1), at: start, calendar: calendar)
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.repeatCount, 10)
        XCTAssertEqual(transition.after.learnedAnchor, start)
        XCTAssertEqual(transition.after.appliedMilestones, [])
        XCTAssertEqual(transition.after.nextDueAt, start.addingTimeInterval(86_400))
    }

    func testReconcileDecayIgnoresNewAndLearningSnapshots() {
        XCTAssertEqual(
            LearningEngine.reconcileDecay(.fresh, rules: rules(), at: start, calendar: calendar).after,
            .fresh
        )
        let learningState = learning(count: 2)
        XCTAssertEqual(
            LearningEngine.reconcileDecay(learningState, rules: rules(), at: start.addingTimeInterval(86_400 * 90), calendar: calendar).after,
            learningState
        )
    }

    func testReconcileDecayRequiresLearnedAnchor() {
        var state = learned(count: 5, anchor: start)
        state.learnedAnchor = nil
        let transition = LearningEngine.reconcileDecay(
            state,
            rules: rules(),
            at: start.addingTimeInterval(86_400 * 90),
            calendar: calendar
        )
        XCTAssertEqual(transition.after, state)
    }

    func testStayingLearnedSchedulesTheNextMilestoneFromTheAnchor() {
        let afterOneDay = start.addingTimeInterval(86_400)
        let transition = LearningEngine.reconcileDecay(
            learned(count: 10, anchor: start),
            rules: rules(threshold: 10, returnBelow: 1),
            at: afterOneDay,
            calendar: calendar
        )
        XCTAssertEqual(transition.after.lifecycle, .learned)
        XCTAssertEqual(transition.after.appliedMilestones, [0])
        XCTAssertEqual(transition.after.nextDueAt, start.addingTimeInterval(3 * 86_400))
    }

    func testMonthEndDecayAppliesTheMonthMilestoneOnce() {
        var utcCalendar = testCalendar()
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let jan31 = testDate("2024-01-31T12:00:00Z")
        let feb29 = testDate("2024-02-29T12:00:00Z")
        let state = learned(count: 5, anchor: jan31, applied: [0, 1, 2, 3])

        let transition = LearningEngine.reconcileDecay(
            state,
            rules: rules(threshold: 5, returnBelow: 1),
            at: feb29,
            calendar: utcCalendar
        )
        XCTAssertEqual(transition.after.repeatCount, 4)
        XCTAssertEqual(transition.after.appliedMilestones, [0, 1, 2, 3, 4])
        XCTAssertNil(transition.after.nextDueAt)
    }

    func testDSTDecayAppliesOneRepeatAtTheNextLocalDay() {
        var newYork = testCalendar(timeZone: "America/New_York")
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeDST = testDate("2025-03-08T17:00:00Z") // 12:00 EST
        let next = LearningEngine.milestoneDate(index: 0, anchor: beforeDST, calendar: newYork)!

        let transition = LearningEngine.reconcileDecay(
            learned(count: 5, anchor: beforeDST),
            rules: rules(threshold: 5, returnBelow: 1),
            at: next,
            calendar: newYork
        )
        XCTAssertEqual(transition.after.repeatCount, 4)
        XCTAssertEqual(transition.after.appliedMilestones, [0])
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
