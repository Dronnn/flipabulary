import Foundation

struct DecayMilestone: Hashable, Sendable {
    let index: Int
    let days: Int?
    let months: Int?
}

enum LearningEngine {
    static let decayMilestones: [DecayMilestone] = [
        DecayMilestone(index: 0, days: 1, months: nil),
        DecayMilestone(index: 1, days: 3, months: nil),
        DecayMilestone(index: 2, days: 7, months: nil),
        DecayMilestone(index: 3, days: 14, months: nil),
        DecayMilestone(index: 4, days: nil, months: 1)
    ]

    // MARK: Grade transitions

    static func grade(
        _ snapshot: LearningSnapshot,
        grade: ReviewGrade,
        rules inputRules: LearningRules,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningTransition {
        let rules = inputRules.normalized
        let before = snapshot
        var after = snapshot
        after.lastGradedAt = date

        switch grade {
        case .good:
            if snapshot.lifecycle == .learned {
                after.repeatCount = min(rules.correctThreshold, snapshot.repeatCount)
                after.lifecycle = .learned
                after.stepIndex = 0
                after.learnedAnchor = date
                after.appliedMilestones = []
                after.nextDueAt = milestoneDate(index: 0, anchor: date, calendar: calendar)
                after.mistakeReturn = false
                return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: false)
            }

            after.repeatCount = min(rules.correctThreshold, snapshot.repeatCount + 1)
            if after.repeatCount >= rules.correctThreshold {
                after.lifecycle = .learned
                after.stepIndex = 0
                after.learnedAnchor = date
                after.appliedMilestones = []
                after.nextDueAt = milestoneDate(index: 0, anchor: date, calendar: calendar)
                after.mistakeReturn = false
                return LearningTransition(before: before, after: after, becameLearned: true, returnedFromLearned: false)
            }

            after.lifecycle = .learning
            after.stepIndex = snapshot.stepIndex + 1
            after.learnedAnchor = nil
            after.appliedMilestones = []
            after.nextDueAt = date.addingTimeInterval(rules.stepInterval(at: after.stepIndex - 1))
            after.mistakeReturn = false
            return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: false)

        case .again:
            after.repeatCount = rules.resetOnMistake ? 0 : snapshot.repeatCount
            after.lifecycle = .learning
            after.stepIndex = 0
            after.learnedAnchor = nil
            after.appliedMilestones = []
            after.nextDueAt = date.addingTimeInterval(rules.stepInterval(at: 0))
            after.mistakeReturn = true
            return LearningTransition(
                before: before,
                after: after,
                becameLearned: false,
                returnedFromLearned: snapshot.lifecycle == .learned
            )
        }
    }

    // MARK: Decay

    static func reconcileDecay(
        _ snapshot: LearningSnapshot,
        rules inputRules: LearningRules,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningTransition {
        let rules = inputRules.normalized
        let before = snapshot
        guard snapshot.lifecycle == .learned,
              rules.autoDecrease,
              let anchor = snapshot.learnedAnchor else {
            return LearningTransition(before: before, after: before, becameLearned: false, returnedFromLearned: false)
        }

        var after = snapshot
        var applied = snapshot.appliedMilestones
        for milestone in decayMilestones where !applied.contains(milestone.index) {
            guard let reached = milestoneDate(index: milestone.index, anchor: anchor, calendar: calendar) else { continue }
            if date >= reached {
                after.repeatCount = max(0, after.repeatCount - 1)
                applied.insert(milestone.index)
            }
        }
        after.appliedMilestones = applied

        if after.repeatCount < rules.returnBelow {
            after.lifecycle = .learning
            after.stepIndex = 0
            after.learnedAnchor = nil
            after.nextDueAt = date
            after.mistakeReturn = true
            return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: true)
        }

        after.nextDueAt = nextMilestoneDate(after: date, anchor: anchor, applied: applied, calendar: calendar)
        return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: false)
    }

    static func reanchorForEnabledDecay(
        _ snapshot: LearningSnapshot,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningSnapshot {
        guard snapshot.lifecycle == .learned else { return snapshot }
        var copy = snapshot
        copy.learnedAnchor = date
        copy.appliedMilestones = []
        copy.nextDueAt = milestoneDate(index: 0, anchor: date, calendar: calendar)
        return copy
    }

    static func milestoneDate(index: Int, anchor: Date, calendar: Calendar) -> Date? {
        guard let milestone = decayMilestones.first(where: { $0.index == index }) else { return nil }
        if let days = milestone.days {
            return calendar.date(byAdding: .day, value: days, to: anchor)
        }
        if let months = milestone.months {
            return calendar.date(byAdding: .month, value: months, to: anchor)
        }
        return nil
    }

    static func nextMilestoneDate(after date: Date, anchor: Date, applied: Set<Int>, calendar: Calendar) -> Date? {
        decayMilestones
            .sorted { $0.index < $1.index }
            .filter { !applied.contains($0.index) }
            .compactMap { milestoneDate(index: $0.index, anchor: anchor, calendar: calendar) }
            .first(where: { $0 > date })
    }

    /// The first future decay milestone that would move this Learned card back to Learning.
    static func nextReturnToLearningDate(
        _ snapshot: LearningSnapshot,
        rules inputRules: LearningRules,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let rules = inputRules.normalized
        guard snapshot.lifecycle == .learned,
              rules.autoDecrease,
              let anchor = snapshot.learnedAnchor else { return nil }

        for milestone in decayMilestones.sorted(by: { $0.index < $1.index })
        where !snapshot.appliedMilestones.contains(milestone.index) {
            guard let reached = milestoneDate(index: milestone.index, anchor: anchor, calendar: calendar),
                  reached > date else { continue }
            let result = reconcileDecay(snapshot, rules: rules, at: reached, calendar: calendar)
            if result.after.lifecycle == .learning {
                return reached
            }
        }
        return nil
    }

    static func isDue(_ snapshot: LearningSnapshot, at date: Date) -> Bool {
        switch snapshot.lifecycle {
        case .learning:
            return (snapshot.nextDueAt ?? .distantPast) <= date
        case .new, .learned:
            return false
        }
    }

    // MARK: Session admission

    struct QueueCandidate: Hashable, Sendable {
        var id: UUID
        var lifecycle: CardLifecycle
        var nextDueAt: Date?
        var createdAt: Date
    }

    struct QueueResult: Equatable, Sendable {
        var admittedIDs: [UUID]
        var learningCount: Int
        var newCount: Int
    }

    static func buildQueue(
        candidates: [QueueCandidate],
        cardsPerSession: Int,
        newCardsPerDay: Int,
        consumedNewCardIDs: Set<UUID>,
        shuffle: Bool,
        seed: UInt64,
        now: Date
    ) -> QueueResult {
        let capacity = min(max(cardsPerSession, 1), 100)
        let quota = min(max(newCardsPerDay, 0), 100)

        var dueLearning = candidates.filter { $0.lifecycle == .learning && ($0.nextDueAt ?? .distantPast) <= now }
        let newCandidates = candidates.filter { $0.lifecycle == .new }
        let remainingNew = max(0, quota - consumedNewCardIDs.count)
        let sessionNew = min(remainingNew, max(0, capacity - dueLearning.count))

        dueLearning.sort { lhs, rhs in
            let l = lhs.nextDueAt ?? .distantPast
            let r = rhs.nextDueAt ?? .distantPast
            if l != r { return l < r }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var newSorted = newCandidates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        if shuffle {
            var generator = SeededGenerator(seed: seed)
            dueLearning.shuffle(using: &generator)
            newSorted.shuffle(using: &generator)
        }

        let admitted = Array(dueLearning.map(\.id).prefix(capacity))
        let availableAfterLearning = max(0, capacity - admitted.count)
        let admittedNew = Array(newSorted.map(\.id).prefix(min(sessionNew, availableAfterLearning)))
        return QueueResult(
            admittedIDs: admitted + admittedNew,
            learningCount: admitted.count,
            newCount: admittedNew.count
        )
    }

    static func actionableDueCount(
        candidates: [QueueCandidate],
        newCardsPerDay: Int,
        consumedNewCardIDs: Set<UUID>,
        now: Date
    ) -> Int {
        let dueLearning = candidates.filter { $0.lifecycle == .learning && ($0.nextDueAt ?? .distantPast) <= now }.count
        let newAvailable = candidates.filter { $0.lifecycle == .new }.count
        let remaining = max(0, min(max(newCardsPerDay, 0), 100) - consumedNewCardIDs.count)
        return dueLearning + min(newAvailable, remaining)
    }

    static func retryDueAt(now: Date, rules: LearningRules) -> Date {
        now.addingTimeInterval(rules.stepInterval(at: 0))
    }

    static let maximumRetryPresentations = 3
}

// MARK: - Deterministic RNG

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
