import XCTest
@testable import flipabulary

@MainActor
final class AppUsageTests: XCTestCase {
    private var clock: MutableClock!
    private var tracker: AppUsageTracker!

    override func setUp() async throws {
        clock = MutableClock(now: testDate("2026-11-07T10:00:00Z"))
        tracker = AppUsageTracker(clock: clock)
    }

    // MARK: Tracker

    func testTrackerDoesNotCountBeforeStart() {
        XCTAssertFalse(tracker.isTracking)
        XCTAssertNil(tracker.liveInterval())
        XCTAssertEqual(tracker.liveSeconds(), 0, accuracy: 0.001)
    }

    func testTrackerStartIsIdempotentAndKeepsTheOriginalStart() {
        tracker.start()
        clock.advance(by: 10)
        tracker.start()
        clock.advance(by: 5)
        XCTAssertTrue(tracker.isTracking)
        XCTAssertEqual(tracker.liveSeconds(), 15, accuracy: 0.001)
    }

    func testTrackerStopReturnsTheIntervalAndResets() {
        tracker.start()
        clock.advance(by: 12)
        let interval = tracker.stop()
        XCTAssertEqual(interval?.start, testDate("2026-11-07T10:00:00Z"))
        XCTAssertEqual(interval?.end, testDate("2026-11-07T10:00:12Z"))
        XCTAssertEqual(interval?.seconds ?? 0, 12, accuracy: 0.001)
        XCTAssertFalse(tracker.isTracking)
        XCTAssertNil(tracker.stop())
        XCTAssertEqual(tracker.liveSeconds(), 0, accuracy: 0.001)
    }

    func testTrackerStopWithoutElapsedTimeReturnsNilButResets() {
        tracker.start()
        XCTAssertNil(tracker.stop())
        XCTAssertFalse(tracker.isTracking)
    }

    func testSetActiveStartsAndStopsTracking() {
        XCTAssertNil(tracker.setActive(true))
        XCTAssertTrue(tracker.isActive)
        XCTAssertTrue(tracker.isTracking)
        clock.advance(by: 5)
        let interval = tracker.setActive(false)
        XCTAssertEqual(interval?.seconds ?? 0, 5, accuracy: 0.001)
        XCTAssertFalse(tracker.isActive)
        XCTAssertFalse(tracker.isTracking)
    }

    func testSetActiveIsIdempotent() {
        tracker.setActive(true)
        clock.advance(by: 5)
        XCTAssertNil(tracker.setActive(true))
        XCTAssertEqual(tracker.liveSeconds(), 5, accuracy: 0.001)

        let interval = tracker.setActive(false)
        XCTAssertEqual(interval?.seconds ?? 0, 5, accuracy: 0.001)
        clock.advance(by: 10)
        XCTAssertNil(tracker.setActive(false))
        XCTAssertEqual(tracker.liveSeconds(), 0, accuracy: 0.001)
    }

    func testInactiveTrackerDoesNotCountOvernightTime() {
        tracker.setActive(true)
        clock.advance(by: 300)
        _ = tracker.setActive(false)

        clock.advance(by: 10 * 3_600)

        XCTAssertFalse(tracker.isActive)
        XCTAssertNil(tracker.liveInterval())
        XCTAssertEqual(tracker.liveSeconds(), 0, accuracy: 0.001)
    }

    func testSetActiveResumesOnlyAfterExplicitActivation() {
        tracker.setActive(true)
        clock.advance(by: 300)
        _ = tracker.setActive(false)
        clock.advance(by: 10 * 3_600)

        tracker.setActive(true)
        clock.advance(by: 120)

        XCTAssertTrue(tracker.isActive)
        XCTAssertEqual(tracker.liveSeconds(), 120, accuracy: 0.001)
    }

    func testTrackerLiveIntervalUsesTheInjectedNow() {
        tracker.start()
        clock.advance(by: 3)
        let now = clock.now.addingTimeInterval(7)
        let interval = tracker.liveInterval(now: now)
        XCTAssertEqual(interval?.seconds ?? 0, 10, accuracy: 0.001)
    }

    func testTrackerClampsBackwardsClockToZero() {
        tracker.start()
        clock.advance(by: -10)
        XCTAssertNil(tracker.liveInterval())
        XCTAssertEqual(tracker.liveSeconds(), 0, accuracy: 0.001)
        XCTAssertNil(tracker.stop())
        XCTAssertFalse(tracker.isTracking)
    }

    func testIntervalSecondsNeverGoesNegative() {
        let now = testDate("2026-11-07T10:00:00Z")
        XCTAssertEqual(AppUsageInterval(start: now, end: now.addingTimeInterval(-1)).seconds, 0, accuracy: 0.001)
        XCTAssertEqual(AppUsageInterval(start: now, end: now.addingTimeInterval(1)).seconds, 1, accuracy: 0.001)
    }

    // MARK: Splitter

    func testSplitterKeepsSameDayUsageInOneBucket() {
        let calendar = testCalendar()
        let start = testDate("2026-11-07T10:00:00Z")
        let end = testDate("2026-11-07T10:05:00Z")
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.dayKey, "2026-11-07")
        XCTAssertEqual(segments.first?.seconds ?? 0, 300, accuracy: 0.001)
    }

    func testSplitterSplitsAcrossMidnight() {
        let calendar = testCalendar()
        let start = testDate("2026-11-06T23:50:00Z")
        let end = testDate("2026-11-07T00:10:00Z")
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].dayKey, "2026-11-06")
        XCTAssertEqual(segments[0].seconds, 600, accuracy: 0.001)
        XCTAssertEqual(segments[1].dayKey, "2026-11-07")
        XCTAssertEqual(segments[1].seconds, 600, accuracy: 0.001)
    }

    func testSplitterHandlesMultipleFullDays() {
        let calendar = testCalendar()
        let start = testDate("2026-11-05T00:00:00Z")
        let end = testDate("2026-11-08T00:00:00Z")
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.map(\.dayKey), ["2026-11-05", "2026-11-06", "2026-11-07"])
        for segment in segments {
            XCTAssertEqual(segment.seconds, 86_400, accuracy: 0.001)
        }
    }

    func testSplitterTreatsExactMidnightAsTheNextDayBoundary() {
        let calendar = testCalendar()
        let start = testDate("2026-11-06T00:00:00Z")
        let end = testDate("2026-11-07T00:00:00Z")
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.dayKey, "2026-11-06")
        XCTAssertEqual(segments.first?.seconds ?? 0, 86_400, accuracy: 0.001)
    }

    func testSplitterIgnoresEmptyAndNegativeIntervals() {
        let calendar = testCalendar()
        let now = testDate("2026-11-07T10:00:00Z")
        XCTAssertTrue(AppUsageDaySplitter.split(from: now, to: now, calendar: calendar).isEmpty)
        XCTAssertTrue(AppUsageDaySplitter.split(from: now, to: now.addingTimeInterval(-60), calendar: calendar).isEmpty)
    }

    func testSplitterUsesTheProvidedTimeZone() {
        let calendar = testCalendar(timeZone: "Asia/Tokyo")
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 1, minute: 0))!
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.map(\.dayKey), ["2026-11-07", "2026-11-08"])
        XCTAssertEqual(segments[0].seconds, 3_600, accuracy: 0.001)
        XCTAssertEqual(segments[1].seconds, 3_600, accuracy: 0.001)
    }

    func testSplitterHandlesDSTSpringForward() {
        let calendar = testCalendar(timeZone: "America/New_York")
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 0))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.dayKey, "2026-03-08")
        XCTAssertEqual(segments.first?.seconds ?? 0, 23 * 3_600, accuracy: 0.001)
    }

    func testSplitterHandlesDSTFallBack() {
        let calendar = testCalendar(timeZone: "America/New_York")
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 0))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.dayKey, "2026-11-01")
        XCTAssertEqual(segments.first?.seconds ?? 0, 25 * 3_600, accuracy: 0.001)
    }

    func testSplitterHandlesHalfOpenDayAtDSTBoundary() {
        let calendar = testCalendar(timeZone: "America/New_York")
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 0))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 0))!
        let segments = AppUsageDaySplitter.split(from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].dayKey, "2026-03-07")
        XCTAssertEqual(segments[0].seconds, 3_600, accuracy: 0.001)
        XCTAssertEqual(segments[1].dayKey, "2026-03-08")
        XCTAssertEqual(segments[1].seconds, 2 * 3_600, accuracy: 0.001)
    }
}
