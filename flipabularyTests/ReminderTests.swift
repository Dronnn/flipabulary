import XCTest
@testable import flipabulary

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private var harness: TestHarness!
    private let calendar = testCalendar()

    override func setUp() async throws {
        harness = try TestHarness(now: testDate("2026-11-07T10:00:00Z"), calendar: testCalendar())
    }

    override func tearDown() async throws {
        harness.finish()
        harness = nil
    }

    private func prefs(
        enabled: Bool = true,
        hour: Int = 20,
        minute: Int = 0,
        weekdays: Set<Int> = Set(1...7),
        sound: Bool = true
    ) -> ReminderPreferences {
        ReminderPreferences(
            enabled: enabled,
            hour: hour,
            minute: minute,
            weekdays: weekdays,
            stackID: nil,
            soundEnabled: sound
        )
    }

    private func work(
        cards: [ReminderCardWork],
        newPerDay: Int = 10,
        consumed: Set<UUID> = [],
        rules: LearningRules = .default
    ) -> ReminderWorkSnapshot {
        ReminderWorkSnapshot(
            stacks: [
                ReminderStackWork(
                    id: UUID(),
                    name: "My words",
                    newPerDay: newPerDay,
                    consumedToday: consumed,
                    rules: rules,
                    cards: cards
                )
            ]
        )
    }

    private func newCard() -> ReminderCardWork {
        ReminderCardWork(lifecycle: .new, repeatCount: 0, nextDueAt: nil, learnedAnchor: nil, appliedMilestones: [])
    }

    func testSevenDayRollingScheduleOnePerDay() {
        let now = harness.clock.now
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(Set(requests.map { CalendarTools.dayKey(for: $0.fireDate, calendar: calendar) }).count, 7)
        XCTAssertTrue(requests.allSatisfy { $0.identifier.hasPrefix(ReminderRequest.identifierPrefix) })
        XCTAssertEqual(requests.first?.fireDate, testDate("2026-11-07T20:00:00Z"))
    }

    func testMultipleTimesCreateRequestsForEachTime() {
        var p = prefs()
        p.times = [
            ReminderTime(hour: 14, minute: 0),
            ReminderTime(hour: 20, minute: 0)
        ]
        let requests = ReminderScheduler.desiredRequests(
            preferences: p,
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: harness.clock.now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 14)
        XCTAssertEqual(Set(requests.map { calendar.component(.hour, from: $0.fireDate) }), [14, 20])
    }

    func testPastTimeStartsNextSelectedDay() {
        let now = testDate("2026-11-07T21:00:00Z")
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.first?.fireDate, testDate("2026-11-08T20:00:00Z"))
        XCTAssertTrue(requests.allSatisfy { $0.fireDate > now })
    }

    func testWeekdaySelection() {
        let now = testDate("2026-11-07T10:00:00Z") // Saturday
        let monday = 2
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(weekdays: [monday]),
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        let weekday = calendar.component(.weekday, from: requests[0].fireDate)
        XCTAssertEqual(weekday, monday)
    }

    func testNoWorkMeansNoRequests() {
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: []),
            now: harness.clock.now,
            calendar: calendar
        )
        XCTAssertTrue(requests.isEmpty)
    }

    func testNewQuotaZeroAndFutureLearningHaveNoWork() {
        let future = ReminderCardWork(
            lifecycle: .learning,
            repeatCount: 2,
            nextDueAt: harness.clock.now.addingTimeInterval(86_400 * 20),
            learnedAnchor: nil,
            appliedMilestones: []
        )
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [newCard(), future], newPerDay: 0),
            now: harness.clock.now,
            calendar: calendar
        )
        XCTAssertTrue(requests.isEmpty)
    }

    func testScheduledLearnedReviewBecomesWorkExactlyWhenDue() {
        let due = harness.clock.now.addingTimeInterval(86_400)
        let learned = ReminderCardWork(
            lifecycle: .learned,
            repeatCount: 9,
            nextDueAt: due,
            learnedAnchor: harness.clock.now,
            appliedMilestones: []
        )
        let snapshot = work(cards: [learned], newPerDay: 0)
        for (date, expected) in [(due.addingTimeInterval(-1), false), (due, true), (due.addingTimeInterval(40 * 86_400), true)] {
            XCTAssertEqual(
                ReminderScheduler.hasWork(scopeID: nil, at: date, isToday: false, work: snapshot, calendar: calendar),
                expected
            )
        }
    }

    func testMasteredCardWithoutDueDateNeverCreatesWork() {
        let mastered = ReminderCardWork(
            lifecycle: .learned,
            repeatCount: 9,
            nextDueAt: nil,
            learnedAnchor: harness.clock.now,
            appliedMilestones: Set(LearningEngine.decayMilestones.map(\.index))
        )
        XCTAssertFalse(ReminderScheduler.hasWork(
            scopeID: nil,
            at: harness.clock.now.addingTimeInterval(365 * 86_400),
            isToday: false,
            work: work(cards: [mastered], newPerDay: 0),
            calendar: calendar
        ))
    }

    func testProcessedDueMilestoneRemainsReminderWorkUntilAnswered() {
        let overdue = ReminderCardWork(
            lifecycle: .learned,
            repeatCount: 8,
            nextDueAt: harness.clock.now.addingTimeInterval(-86_400),
            learnedAnchor: harness.clock.now.addingTimeInterval(-2 * 86_400),
            appliedMilestones: [0]
        )
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [overdue], newPerDay: 0),
            now: harness.clock.now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 7)
    }

    func testPermissionStates() {
        for authorization in [ReminderAuthorization.notDetermined, .denied, .unknown] {
            let requests = ReminderScheduler.desiredRequests(
                preferences: prefs(),
                authorization: authorization,
                work: work(cards: [newCard()]),
                now: harness.clock.now,
                calendar: calendar
            )
            XCTAssertTrue(requests.isEmpty, "\(authorization)")
        }
        for authorization in [ReminderAuthorization.authorized, .provisional, .ephemeral] {
            let requests = ReminderScheduler.desiredRequests(
                preferences: prefs(),
                authorization: authorization,
                work: work(cards: [newCard()]),
                now: harness.clock.now,
                calendar: calendar
            )
            XCTAssertEqual(requests.count, 7, "\(authorization)")
        }
    }

    func testDSTKeepsOneResolvedFireDatePerLocalDay() {
        var newYork = testCalendar(timeZone: "America/New_York")
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let now = testDate("2025-03-07T15:00:00Z") // 10:00 EST before spring forward
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: now,
            calendar: newYork
        )
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(Set(requests.map { CalendarTools.dayKey(for: $0.fireDate, calendar: newYork) }).count, 7)
        for request in requests {
            XCTAssertEqual(newYork.component(.hour, from: request.fireDate), 20)
        }
    }

    func testTravelTimezoneUsesLocalCalendar() {
        var tokyo = testCalendar(timeZone: "Asia/Tokyo")
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let requests = ReminderScheduler.desiredRequests(
            preferences: prefs(),
            authorization: .authorized,
            work: work(cards: [newCard()]),
            now: testDate("2026-11-07T10:00:00Z"),
            calendar: tokyo
        )
        XCTAssertEqual(requests.first?.fireDate, testDate("2026-11-07T11:00:00Z"))
    }

    func testServiceSchedulesAndCancelsOwnedRequestsWhilePreservingForeign() async {
        let stack = harness.makeStack()
        harness.makeCard(word: "new", stack: stack)
        try? harness.save()
        harness.preferences.preferences.reminders = prefs()
        harness.notifications.pending["foreign.request"] = ReminderRequest(
            identifier: "foreign.request",
            fireDate: harness.clock.now,
            scopeID: nil,
            soundEnabled: true
        )

        await harness.reminders.refreshAndReconcile()
        XCTAssertTrue(harness.preferences.preferences.reminders.enabled)
        let owned = harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }
        XCTAssertEqual(owned.count, 7)
        XCTAssertNotNil(harness.notifications.pending["foreign.request"])
        XCTAssertNotNil(harness.reminders.nextScheduledAt)

        harness.preferences.preferences.reminders.enabled = false
        await harness.reminders.reconcile()
        XCTAssertTrue(harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }.isEmpty)
        XCTAssertNotNil(harness.notifications.pending["foreign.request"])
        XCTAssertNil(harness.reminders.nextScheduledAt)
    }

    func testServiceSchedulesReminderStartingOnLearnedDueDay() async {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let card = harness.makeCard(
            word: "learned",
            stack: stack,
            lifecycle: .learned,
            repeatCount: 5,
            nextDueAt: harness.clock.now.addingTimeInterval(86_400)
        )
        card.learningState?.learnedAnchor = harness.clock.now
        card.learningState?.appliedMilestones = []
        try? harness.save()
        harness.preferences.preferences.reminders = prefs()

        await harness.reminders.refreshAndReconcile()

        let owned = harness.notifications.pending.values.filter { $0.identifier.hasPrefix(ReminderRequest.identifierPrefix) }
        XCTAssertEqual(owned.count, 6)
        XCTAssertEqual(owned.map(\.fireDate).min(), testDate("2026-11-08T20:00:00Z"))
        XCTAssertFalse(owned.contains { CalendarTools.dayKey(for: $0.fireDate, calendar: calendar) == "2026-11-07" })
    }

    func testDeniedPermissionLeavesTruthfulDisabledState() async {
        let stack = harness.makeStack()
        harness.makeCard(word: "new", stack: stack)
        try? harness.save()
        harness.notifications.status = .denied
        harness.notifications.grantsAuthorization = false
        harness.preferences.preferences.reminders = prefs(enabled: false)

        await harness.reminders.setEnabled(true)
        XCTAssertFalse(harness.preferences.preferences.reminders.enabled)
        XCTAssertEqual(harness.reminders.authorization, .denied)
        XCTAssertEqual(harness.notifications.requestAuthorizationCallCount, 1)
        XCTAssertTrue(harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }.isEmpty)
    }

    func testPermissionRevokedExternallyDisablesAndCancels() async {
        let stack = harness.makeStack()
        harness.makeCard(word: "new", stack: stack)
        try? harness.save()
        harness.preferences.preferences.reminders = prefs()
        await harness.reminders.refreshAndReconcile()
        XCTAssertEqual(harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }.count, 7)

        harness.notifications.status = .denied
        await harness.reminders.refreshAndReconcile()
        XCTAssertFalse(harness.preferences.preferences.reminders.enabled)
        XCTAssertTrue(harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }.isEmpty)
    }

    func testTestReminderIsSeparateAndDoesNotChangeDailyScheduleOrQuota() async {
        let stack = harness.makeStack()
        harness.makeCard(word: "new", stack: stack)
        try? harness.save()
        harness.preferences.preferences.reminders = prefs()
        await harness.reminders.refreshAndReconcile()
        let before = Set(harness.notifications.pending.keys)

        await harness.reminders.sendTestReminder()
        XCTAssertTrue(harness.notifications.pending.keys.contains(ReminderRequest.testIdentifier))
        let daily = harness.notifications.pending.keys.filter { $0 != ReminderRequest.testIdentifier }
        XCTAssertEqual(Set(daily), before)
        XCTAssertEqual(harness.maintenance.consumedNewCardIDs(stackID: stack.id).count, 0)
    }

    func testNoWorkDaysSkipScheduling() async {
        let stack = harness.makeStack(newCardsPerDay: 0)
        let card = harness.makeCard(
            word: "learned",
            stack: stack,
            lifecycle: .learned,
            repeatCount: 5,
            nextDueAt: harness.clock.now.addingTimeInterval(86_400 * 30)
        )
        card.learningState?.learnedAnchor = harness.clock.now
        card.learningState?.appliedMilestones = []
        try? harness.save()
        harness.preferences.preferences.reminders = prefs()
        await harness.reminders.refreshAndReconcile()
        XCTAssertTrue(harness.notifications.pending.keys.filter { $0.hasPrefix(ReminderRequest.identifierPrefix) }.isEmpty)
        XCTAssertEqual(harness.reminders.nextScheduledText(), "All caught up. No review work is expected in the next seven days.")
    }
}
