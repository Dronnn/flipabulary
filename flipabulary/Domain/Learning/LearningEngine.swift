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
                after.repeatCount = rules.correctThreshold
                after.lifecycle = .learned
                after.stepIndex = 0
                after.learnedAnchor = snapshot.learnedAnchor ?? date
                after.mistakeReturn = false

                let completed = snapshot.appliedMilestones
                guard completed.count < decayMilestones.count else {
                    after.appliedMilestones = completed
                    after.nextDueAt = nil
                    return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: false)
                }

                let reviewIndex = decayMilestones.map(\.index).first(where: { !completed.contains($0) }) ?? 0
                var applied = completed
                applied.insert(reviewIndex)
                after.appliedMilestones = applied
                after.nextDueAt = applied.count >= decayMilestones.count
                    ? nil
                    : milestoneDate(index: reviewIndex + 1, anchor: date, calendar: calendar)
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

    // MARK: Learned reviews

    /// Learned reviews are scheduled when the card is graded. This reconciliation only
    /// repairs older learned cards that have no due date yet; it never removes progress.
    static func reconcileDecay(
        _ snapshot: LearningSnapshot,
        rules inputRules: LearningRules,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningTransition {
        let before = snapshot
        guard snapshot.lifecycle == .learned,
              snapshot.appliedMilestones.count < decayMilestones.count,
              snapshot.nextDueAt == nil else {
            return LearningTransition(before: before, after: before, becameLearned: false, returnedFromLearned: false)
        }

        var after = snapshot
        after.nextDueAt = milestoneDate(index: 0, anchor: date, calendar: calendar)
        return LearningTransition(before: before, after: after, becameLearned: false, returnedFromLearned: false)
    }

    static func reanchorForEnabledDecay(
        _ snapshot: LearningSnapshot,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningSnapshot {
        snapshot
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

    static func isDue(_ snapshot: LearningSnapshot, at date: Date) -> Bool {
        switch snapshot.lifecycle {
        case .learning:
            return (snapshot.nextDueAt ?? .distantPast) <= date
        case .learned:
            guard snapshot.appliedMilestones.count < decayMilestones.count else { return false }
            guard let due = snapshot.nextDueAt else { return false }
            return due <= date
        case .new:
            return false
        }
    }

    // MARK: Session admission

    struct QueueCandidate: Hashable, Sendable {
        var id: UUID
        var lifecycle: CardLifecycle
        var nextDueAt: Date?
        var createdAt: Date
        var appliedMilestoneCount: Int = 0
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

        var dueLearning = candidates.filter { candidate in
            switch candidate.lifecycle {
            case .learning:
                return (candidate.nextDueAt ?? .distantPast) <= now
            case .learned:
                guard candidate.appliedMilestoneCount < decayMilestones.count else { return false }
                guard let due = candidate.nextDueAt else { return false }
                return due <= now
            case .new:
                return false
            }
        }
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
        let dueLearning = candidates.filter { candidate in
            switch candidate.lifecycle {
            case .learning:
                return (candidate.nextDueAt ?? .distantPast) <= now
            case .learned:
                guard candidate.appliedMilestoneCount < decayMilestones.count else { return false }
                guard let due = candidate.nextDueAt else { return false }
                return due <= now
            case .new:
                return false
            }
        }.count
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
