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
        var after = reconcileDecay(snapshot, rules: rules, at: date, calendar: calendar).after
        after.lastGradedAt = date

        if grade == .again {
            after = .fresh
            after.lifecycle = .learning
            after.lastGradedAt = date
            after.nextDueAt = date.addingTimeInterval(rules.stepInterval(at: 0))
            after.mistakeReturn = true
        } else if snapshot.lifecycle == .new {
            after.lifecycle = .learning
            after.repeatCount = 1
            after.stepIndex = 0
            after.nextDueAt = date.addingTimeInterval(rules.stepInterval(at: 0))
        } else if isDue(after, at: date) {
            after.repeatCount += 1
            after.mistakeReturn = false
            if after.lifecycle == .learning {
                let nextStep = after.stepIndex + 1
                if nextStep < rules.steps.count {
                    after.stepIndex = nextStep
                    after.nextDueAt = date.addingTimeInterval(rules.stepInterval(at: nextStep))
                } else {
                    after.lifecycle = .learned
                    after.stepIndex = rules.steps.count
                    after.reviewStageIndex = 0
                    after.learnedAnchor = date
                    after.appliedMilestones = []
                    after.nextDueAt = milestoneDate(index: 0, anchor: date, calendar: calendar)
                }
            } else {
                after.reviewStageIndex += 1
                after.learnedAnchor = date
                after.nextDueAt = milestoneDate(index: after.reviewStageIndex, anchor: date, calendar: calendar)
            }
        }

        return LearningTransition(
            before: snapshot,
            after: after,
            becameLearned: snapshot.lifecycle != .learned && after.lifecycle == .learned,
            returnedFromLearned: snapshot.lifecycle == .learned && after.lifecycle == .learning
        )
    }

    // MARK: Due review decay

    /// A long review decays once when due. Only an answer can move to the next stage.
    static func reconcileDecay(
        _ snapshot: LearningSnapshot,
        rules: LearningRules,
        at date: Date,
        calendar: Calendar = .current
    ) -> LearningTransition {
        var after = snapshot
        if snapshot.lifecycle == .learned,
           snapshot.reviewStageIndex < decayMilestones.count,
           isDue(snapshot, at: date),
           !snapshot.appliedMilestones.contains(snapshot.reviewStageIndex) {
            after.repeatCount = max(0, snapshot.repeatCount - 1)
            after.appliedMilestones.insert(snapshot.reviewStageIndex)
        }
        return LearningTransition(before: snapshot, after: after, becameLearned: false, returnedFromLearned: false)
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

    static func isDue(_ snapshot: LearningSnapshot, at date: Date) -> Bool {
        switch snapshot.lifecycle {
        case .learning:
            return (snapshot.nextDueAt ?? .distantPast) <= date
        case .learned:
            return snapshot.nextDueAt.map { $0 <= date } ?? false
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
    }

    private static func isDue(_ candidate: QueueCandidate, at date: Date) -> Bool {
        switch candidate.lifecycle {
        case .new: false
        case .learning: (candidate.nextDueAt ?? .distantPast) <= date
        case .learned: candidate.nextDueAt.map { $0 <= date } ?? false
        }
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

        var dueLearning = candidates.filter { isDue($0, at: now) }
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
        let dueLearning = candidates.filter { isDue($0, at: now) }.count
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
