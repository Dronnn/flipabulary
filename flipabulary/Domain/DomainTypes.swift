import Foundation

// MARK: - Lifecycle and grading

enum CardLifecycle: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case learned

    var title: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .learned: "Learned"
        }
    }
}

enum CardPresentationOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case frontFirst
    case backFirst
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontFirst: "Front first"
        case .backFirst: "Translation first"
        case .mixed: "Mixed"
        }
    }

    var translationFirst: Bool {
        self == .backFirst
    }
}

enum ReviewGrade: String, Codable, CaseIterable, Sendable {
    case again
    case good

    var title: String {
        switch self {
        case .again: "Again"
        case .good: "Good"
        }
    }
}

enum CardFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case learning
    case learned
    case new
    case difficult

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .learning: "Learning"
        case .learned: "Learned"
        case .new: "New"
        case .difficult: "Difficult"
        }
    }

    func matches(lifecycle: CardLifecycle, isDifficult: @autoclosure () -> Bool) -> Bool {
        switch self {
        case .all: true
        case .learning: lifecycle == .learning
        case .learned: lifecycle == .learned
        case .new: lifecycle == .new
        case .difficult: isDifficult()
        }
    }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }
}

enum ReviewSessionStatus: String, Codable, Sendable {
    case active
    case completed
    case abandoned
}

// MARK: - Rules

struct LearningRules: Codable, Equatable, Sendable {
    static let minimumThreshold = 1
    static let maximumThreshold = 20

    var correctThreshold: Int
    var resetOnMistake: Bool
    var autoDecrease: Bool
    var returnBelow: Int
    var steps: [TimeInterval]
    var version: Int

    static let `default` = LearningRules(
        correctThreshold: 5,
        resetOnMistake: true,
        autoDecrease: true,
        returnBelow: 5,
        steps: [60, 300, 600, 1_800, 3_600, 10_800, 43_200, 86_400],
        version: 1
    )

    static let defaultSteps: [TimeInterval] = [60, 300, 600, 1_800, 3_600, 10_800, 43_200, 86_400]

    var normalized: LearningRules {
        var copy = self
        copy.correctThreshold = min(max(copy.correctThreshold, Self.minimumThreshold), Self.maximumThreshold)
        copy.returnBelow = min(max(copy.returnBelow, 1), copy.correctThreshold)
        copy.steps = Self.validatedSteps(copy.steps)
        return copy
    }

    static func validatedSteps(_ steps: [TimeInterval]) -> [TimeInterval] {
        guard !steps.isEmpty else { return defaultSteps }
        var previous: TimeInterval = 0
        var result: [TimeInterval] = []
        for step in steps {
            guard step > 0, step.isFinite, step > previous else { return defaultSteps }
            result.append(step)
            previous = step
        }
        return result
    }

    func stepInterval(at index: Int) -> TimeInterval {
        guard !steps.isEmpty else { return 60 }
        return steps[min(max(index, 0), steps.count - 1)]
    }

    var thresholdExplanation: String {
        "A word becomes Learned after \(correctThreshold) correct \(correctThreshold == 1 ? "answer" : "answers") in a row."
    }

    var returnExplanation: String {
        "A Learned word returns to Learning when fewer than \(returnBelow) repeats remain."
    }

    var decaySummary: String {
        "1d · 3d · 7d · 2w · 1mo"
    }
}

// MARK: - Session configuration

struct SessionConfig: Codable, Equatable, Sendable {
    var stackID: UUID
    var cardsPerSession: Int
    var newCardsPerDay: Int
    var shuffle: Bool
    var translationFirst: Bool
    var steps: [TimeInterval]
    var rules: LearningRules
    var seed: UInt64
    var presentationMode: CardPresentationOrder? = nil

    var rulesVersion: Int { rules.version }

    var effectivePresentationMode: CardPresentationOrder {
        presentationMode ?? (translationFirst ? .backFirst : .frontFirst)
    }

    func nextShowsTranslationFirst() -> Bool {
        switch effectivePresentationMode {
        case .frontFirst: false
        case .backFirst: true
        case .mixed: Bool.random()
        }
    }

    func normalized() -> SessionConfig {
        var copy = self
        copy.cardsPerSession = min(max(copy.cardsPerSession, 1), 100)
        copy.newCardsPerDay = min(max(copy.newCardsPerDay, 0), 100)
        copy.steps = LearningRules.validatedSteps(copy.steps)
        copy.rules = copy.rules.normalized
        return copy
    }
}

// MARK: - Review persistence payloads

struct ReviewPresentation: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var cardID: UUID
    var isRetry: Bool
    var retryNumber: Int
    var availableAt: Date
    var gradedAt: Date?
    var translationFirst: Bool? = nil
}

struct ReviewQueueEnvelope: Codable, Equatable, Sendable {
    var presentations: [ReviewPresentation]
    var admittedCardIDs: [UUID]
    var retryCounts: [UUID: Int]
    var nextRetryAt: Date?
}

// MARK: - Learning value snapshots

struct LearningSnapshot: Equatable, Sendable {
    var repeatCount: Int
    var lifecycle: CardLifecycle
    var stepIndex: Int
    var nextDueAt: Date?
    var lastGradedAt: Date?
    var learnedAnchor: Date?
    var appliedMilestones: Set<Int>
    var mistakeReturn: Bool

    static let fresh = LearningSnapshot(
        repeatCount: 0,
        lifecycle: .new,
        stepIndex: 0,
        nextDueAt: nil,
        lastGradedAt: nil,
        learnedAnchor: nil,
        appliedMilestones: [],
        mistakeReturn: false
    )
}

struct LearningTransition: Equatable, Sendable {
    var before: LearningSnapshot
    var after: LearningSnapshot
    var becameLearned: Bool
    var returnedFromLearned: Bool
}

// MARK: - Search and display projections

struct CardHistoryItem: Hashable, Sendable {
    var grade: ReviewGrade
    var timestamp: Date
}

struct CardDisplayModel: Identifiable, Hashable, Sendable {
    var id: UUID
    var word: String
    var translation: String
    var sourceExample: String?
    var translatedExample: String?
    var phonetic: String?
    var partOfSpeech: String?
    var stackID: UUID
    var stackName: String
    var tagNames: [String]
    var lifecycle: CardLifecycle
    var repeatCount: Int
    var threshold: Int
    var nextDueAt: Date?
    var createdAt: Date
    var recentGrades: [CardHistoryItem]
    var difficultOverride: Bool? = nil

    var progress: Double {
        guard threshold > 0 else { return 0 }
        return Double(min(repeatCount, threshold)) / Double(threshold)
    }

    var isDifficult: Bool {
        if let difficultOverride { return difficultOverride }
        return recentGrades.prefix(5).filter { $0.grade == .again }.count >= 2
    }
}

struct StackDisplayModel: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var savedCount: Int
    var dueCount: Int
    var learnedCount: Int
}

struct CategorySummary: Identifiable, Hashable, Sendable {
    var filter: CardFilter
    var count: Int

    var id: String { filter.rawValue }
}

struct LibrarySummary: Sendable {
    var saved: Int
    var due: Int
    var new: Int
    var learning: Int
    var learned: Int
    var difficult: Int

    var learnedProgress: Double {
        guard saved > 0 else { return 0 }
        return Double(learned) / Double(saved)
    }

    var counts: [CategorySummary] {
        [
            CategorySummary(filter: .new, count: new),
            CategorySummary(filter: .learning, count: learning),
            CategorySummary(filter: .learned, count: learned),
            CategorySummary(filter: .difficult, count: difficult)
        ]
    }
}
