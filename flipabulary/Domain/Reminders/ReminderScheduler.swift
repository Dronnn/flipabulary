import Foundation

enum ReminderAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .denied: "Notifications are off in system settings"
        case .authorized: "Allowed"
        case .provisional: "Quiet delivery allowed"
        case .ephemeral: "Temporary delivery allowed"
        case .unknown: "Status unavailable"
        }
    }
}

struct ReminderCardWork: Sendable {
    var lifecycle: CardLifecycle
    var repeatCount: Int
    var nextDueAt: Date?
    var learnedAnchor: Date?
    var appliedMilestones: Set<Int>
}

struct ReminderStackWork: Sendable {
    var id: UUID
    var name: String
    var newPerDay: Int
    var consumedToday: Set<UUID>
    var rules: LearningRules
    var cards: [ReminderCardWork]
    var newCount: Int = 0
    var earliestLearningDue: Date? = nil
    var earliestLearnedDue: Date? = nil
}

struct ReminderWorkSnapshot: Sendable {
    var stacks: [ReminderStackWork]
}

struct ReminderRequest: Equatable, Sendable {
    var identifier: String
    var fireDate: Date
    var scopeID: UUID?
    var isTest: Bool = false
    var soundEnabled: Bool

    static let identifierPrefix = "flipabulary.reminder."
    static let testIdentifier = "flipabulary.reminder.test"

    var isFeatureOwned: Bool { identifier.hasPrefix(Self.identifierPrefix) }
}

enum ReminderScheduler {
    static let horizonDays = 7

    static func desiredRequests(
        preferences: ReminderPreferences,
        authorization: ReminderAuthorization,
        work: ReminderWorkSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> [ReminderRequest] {
        guard preferences.enabled, authorization.allowsScheduling else { return [] }

        let scopeKey: String
        if let stackID = preferences.stackID,
           work.stacks.contains(where: { $0.id == stackID }) {
            scopeKey = stackID.uuidString
        } else {
            scopeKey = "all"
        }

        let todayKey = CalendarTools.dayKey(for: now, calendar: calendar)
        var requests: [ReminderRequest] = []
        for time in preferences.allTimes {
            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                let dayKey = CalendarTools.dayKey(for: day, calendar: calendar)
                guard let fireDate = CalendarTools.date(
                    onDayContaining: day,
                    hour: time.hour,
                    minute: time.minute,
                    calendar: calendar
                ), fireDate > now else { continue }

                let weekday = calendar.component(.weekday, from: fireDate)
                guard preferences.weekdays.contains(weekday) else { continue }
                guard hasWork(
                    scopeID: preferences.stackID,
                    at: fireDate,
                    isToday: dayKey == todayKey,
                    work: work,
                    calendar: calendar
                ) else { continue }

                requests.append(
                    ReminderRequest(
                        identifier: "\(ReminderRequest.identifierPrefix)\(scopeKey).\(time.id.uuidString).\(dayKey)",
                        fireDate: fireDate,
                        scopeID: preferences.stackID,
                        soundEnabled: preferences.soundEnabled
                    )
                )
            }
        }
        return requests.sorted { $0.fireDate < $1.fireDate }
    }

    static func hasWork(
        scopeID: UUID?,
        at date: Date,
        isToday: Bool,
        work: ReminderWorkSnapshot,
        calendar: Calendar = .current
    ) -> Bool {
        let stacks = work.stacks.filter { scopeID == nil || $0.id == scopeID }
        for stack in stacks {
            let newCount: Int
            let earliestLearning: Date?
            let earliestLearned: Date?

            if stack.cards.isEmpty {
                newCount = stack.newCount
                earliestLearning = stack.earliestLearningDue
                earliestLearned = stack.earliestLearnedDue
            } else {
                newCount = stack.cards.lazy.filter { $0.lifecycle == .new }.count
                earliestLearning = stack.cards.compactMap { card in
                    card.lifecycle == .learning ? card.nextDueAt : nil
                }.min()
                earliestLearned = stack.cards.compactMap { card in
                    guard card.lifecycle == .learned,
                          card.appliedMilestones.count < LearningEngine.decayMilestones.count else { return nil }
                    return card.nextDueAt
                }.min()
            }

            if stack.newPerDay > 0 {
                let consumed = isToday ? stack.consumedToday.count : 0
                if newCount > 0, stack.newPerDay - consumed > 0 { return true }
            }
            if let earliestLearning, earliestLearning <= date { return true }
            if let earliestLearned, earliestLearned <= date { return true }
        }
        return false
    }

    static func nextScheduledDate(in requests: [ReminderRequest]) -> Date? {
        requests.map(\.fireDate).min()
    }
}
