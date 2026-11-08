import Foundation

struct AppUsageInterval: Sendable, Equatable {
    var start: Date
    var end: Date

    var seconds: Double {
        max(0, end.timeIntervalSince(start))
    }
}

enum AppUsageDaySplitter {
    static func split(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [(dayKey: String, seconds: Double)] {
        guard end > start else { return [] }
        var totals: [String: Double] = [:]
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  nextDay > cursor else {
                let key = CalendarTools.dayKey(for: cursor, calendar: calendar)
                totals[key, default: 0] += end.timeIntervalSince(cursor)
                break
            }
            let segmentEnd = min(end, nextDay)
            let key = CalendarTools.dayKey(for: cursor, calendar: calendar)
            totals[key, default: 0] += segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
        }
        return totals
            .map { (dayKey: $0.key, seconds: $0.value) }
            .sorted { $0.dayKey < $1.dayKey }
    }
}

@MainActor
final class AppUsageTracker {
    private let clock: DateProviding
    private(set) var startedAt: Date?
    private(set) var isActive = false

    init(clock: DateProviding = SystemClock()) {
        self.clock = clock
    }

    var isTracking: Bool { startedAt != nil }

    @discardableResult
    func setActive(_ active: Bool) -> AppUsageInterval? {
        guard active != isActive else { return nil }
        if active {
            start()
            return nil
        }
        return stop()
    }

    func start() {
        isActive = true
        guard startedAt == nil else { return }
        startedAt = clock.now
    }

    @discardableResult
    func stop() -> AppUsageInterval? {
        isActive = false
        guard let start = startedAt else { return nil }
        startedAt = nil
        return interval(from: start, to: clock.now)
    }

    func liveInterval(now: Date? = nil) -> AppUsageInterval? {
        guard let start = startedAt else { return nil }
        return interval(from: start, to: now ?? clock.now)
    }

    func liveSeconds(now: Date? = nil) -> Double {
        liveInterval(now: now)?.seconds ?? 0
    }

    private func interval(from start: Date, to end: Date) -> AppUsageInterval? {
        guard end > start else { return nil }
        return AppUsageInterval(start: start, end: end)
    }
}
