import Foundation
import SwiftData

// MARK: - Stack

@Model
final class VocabularyStack {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var cardsPerSession: Int
    var newCardsPerDay: Int
    var shuffleOrder: Bool
    var translationFirst: Bool
    var stepsData: Data?
    var customRulesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \VocabularyCard.stack)
    var cards: [VocabularyCard] = []

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        cardsPerSession: Int = 20,
        newCardsPerDay: Int = 10,
        shuffleOrder: Bool = true,
        translationFirst: Bool = false,
        steps: [TimeInterval] = LearningRules.defaultSteps
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.cardsPerSession = cardsPerSession
        self.newCardsPerDay = newCardsPerDay
        self.shuffleOrder = shuffleOrder
        self.translationFirst = translationFirst
        self.stepsData = try? JSONEncoder().encode(steps)
        self.customRulesData = nil
    }

    var steps: [TimeInterval] {
        get {
            guard let data = stepsData,
                  let decoded = try? JSONDecoder().decode([TimeInterval].self, from: data),
                  !decoded.isEmpty else { return LearningRules.defaultSteps }
            return decoded
        }
        set {
            stepsData = try? JSONEncoder().encode(LearningRules.validatedSteps(newValue))
            updatedAt = Date()
        }
    }

    var customRules: LearningRules? {
        get {
            guard let data = customRulesData else { return nil }
            return try? JSONDecoder().decode(LearningRules.self, from: data)
        }
        set {
            customRulesData = newValue.flatMap { try? JSONEncoder().encode($0.normalized) }
            updatedAt = Date()
        }
    }

    func effectiveRules(global: LearningRules) -> LearningRules {
        (customRules ?? global).normalized
    }

    func makeSessionConfig(globalRules: LearningRules, seed: UInt64) -> SessionConfig {
        SessionConfig(
            stackID: id,
            cardsPerSession: min(max(cardsPerSession, 1), 100),
            newCardsPerDay: min(max(newCardsPerDay, 0), 100),
            shuffle: shuffleOrder,
            translationFirst: translationFirst,
            steps: steps,
            rules: effectiveRules(global: globalRules),
            seed: seed
        ).normalized()
    }
}

// MARK: - Tag

@Model
final class VocabularyTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(inverse: \VocabularyCard.tags)
    var cards: [VocabularyCard] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - Card

@Model
final class VocabularyCard {
    @Attribute(.unique) var id: UUID
    var word: String
    var translation: String
    var sourceExample: String?
    var translatedExample: String?
    var phonetic: String?
    var partOfSpeech: String?
    var createdAt: Date
    var updatedAt: Date

    var stack: VocabularyStack?

    @Relationship(deleteRule: .nullify)
    var tags: [VocabularyTag] = []

    @Relationship(deleteRule: .cascade, inverse: \CardLearningState.card)
    var learningState: CardLearningState?

    @Relationship(deleteRule: .cascade, inverse: \ReviewEvent.card)
    var reviewEvents: [ReviewEvent] = []

    init(
        id: UUID = UUID(),
        word: String,
        translation: String,
        sourceExample: String? = nil,
        translatedExample: String? = nil,
        phonetic: String? = nil,
        partOfSpeech: String? = nil,
        stack: VocabularyStack?,
        tags: [VocabularyTag] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.translation = translation
        self.sourceExample = sourceExample
        self.translatedExample = translatedExample
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.stack = stack
        self.tags = tags
        self.learningState = CardLearningState(card: self)
        self.reviewEvents = []
    }

    var snapshot: LearningSnapshot {
        learningState?.snapshot ?? .fresh
    }

    var sortedEvents: [ReviewEvent] {
        reviewEvents.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Learning state

@Model
final class CardLearningState {
    @Attribute(.unique) var id: UUID
    var repeatCount: Int
    var lifecycleRaw: String
    var stepIndex: Int
    var nextDueAt: Date?
    var lastGradedAt: Date?
    var learnedAnchor: Date?
    var appliedMilestonesData: Data?
    var mistakeReturn: Bool
    var totalGrades: Int
    var rulesVersion: Int

    var card: VocabularyCard?

    init(
        id: UUID = UUID(),
        repeatCount: Int = 0,
        lifecycle: CardLifecycle = .new,
        stepIndex: Int = 0,
        nextDueAt: Date? = nil,
        lastGradedAt: Date? = nil,
        learnedAnchor: Date? = nil,
        appliedMilestones: Set<Int> = [],
        mistakeReturn: Bool = false,
        totalGrades: Int = 0,
        rulesVersion: Int = LearningRules.default.version,
        card: VocabularyCard? = nil
    ) {
        self.id = id
        self.repeatCount = repeatCount
        self.lifecycleRaw = lifecycle.rawValue
        self.stepIndex = stepIndex
        self.nextDueAt = nextDueAt
        self.lastGradedAt = lastGradedAt
        self.learnedAnchor = learnedAnchor
        self.appliedMilestonesData = try? JSONEncoder().encode(Array(appliedMilestones).sorted())
        self.mistakeReturn = mistakeReturn
        self.totalGrades = totalGrades
        self.rulesVersion = rulesVersion
        self.card = card
    }

    var lifecycle: CardLifecycle {
        get { CardLifecycle(rawValue: lifecycleRaw) ?? .new }
        set { lifecycleRaw = newValue.rawValue }
    }

    var appliedMilestones: Set<Int> {
        get {
            guard let data = appliedMilestonesData,
                  let decoded = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
            return Set(decoded)
        }
        set {
            appliedMilestonesData = try? JSONEncoder().encode(Array(newValue).sorted())
        }
    }

    var snapshot: LearningSnapshot {
        LearningSnapshot(
            repeatCount: repeatCount,
            lifecycle: lifecycle,
            stepIndex: stepIndex,
            nextDueAt: nextDueAt,
            lastGradedAt: lastGradedAt,
            learnedAnchor: learnedAnchor,
            appliedMilestones: appliedMilestones,
            mistakeReturn: mistakeReturn
        )
    }

    func apply(_ snapshot: LearningSnapshot, rulesVersion: Int) {
        repeatCount = snapshot.repeatCount
        lifecycle = snapshot.lifecycle
        stepIndex = snapshot.stepIndex
        nextDueAt = snapshot.nextDueAt
        lastGradedAt = snapshot.lastGradedAt
        learnedAnchor = snapshot.learnedAnchor
        appliedMilestones = snapshot.appliedMilestones
        mistakeReturn = snapshot.mistakeReturn
        self.rulesVersion = rulesVersion
    }
}

// MARK: - Review event

@Model
final class ReviewEvent {
    @Attribute(.unique) var id: UUID
    var presentationID: UUID
    var sessionID: UUID
    var cardID: UUID
    var gradeRaw: String
    var timestamp: Date
    var beforeRepeatCount: Int
    var afterRepeatCount: Int
    var beforeLifecycleRaw: String
    var afterLifecycleRaw: String
    var rulesVersion: Int

    var card: VocabularyCard?

    init(
        id: UUID = UUID(),
        presentationID: UUID,
        sessionID: UUID,
        cardID: UUID,
        grade: ReviewGrade,
        timestamp: Date,
        beforeRepeatCount: Int,
        afterRepeatCount: Int,
        beforeLifecycle: CardLifecycle,
        afterLifecycle: CardLifecycle,
        rulesVersion: Int,
        card: VocabularyCard?
    ) {
        self.id = id
        self.presentationID = presentationID
        self.sessionID = sessionID
        self.cardID = cardID
        self.gradeRaw = grade.rawValue
        self.timestamp = timestamp
        self.beforeRepeatCount = beforeRepeatCount
        self.afterRepeatCount = afterRepeatCount
        self.beforeLifecycleRaw = beforeLifecycle.rawValue
        self.afterLifecycleRaw = afterLifecycle.rawValue
        self.rulesVersion = rulesVersion
        self.card = card
    }

    var grade: ReviewGrade {
        ReviewGrade(rawValue: gradeRaw) ?? .good
    }

    var beforeLifecycle: CardLifecycle {
        CardLifecycle(rawValue: beforeLifecycleRaw) ?? .new
    }

    var afterLifecycle: CardLifecycle {
        CardLifecycle(rawValue: afterLifecycleRaw) ?? .new
    }
}

// MARK: - Session

@Model
final class ReviewSession {
    @Attribute(.unique) var id: UUID
    var stackID: UUID
    var startedAt: Date
    var endedAt: Date?
    var lastActiveAt: Date
    var activeSeconds: Double
    var statusRaw: String
    var configData: Data?
    var queueData: Data?
    var committedPresentationIDsData: Data?
    var goodCount: Int
    var againCount: Int
    var currentPresentationID: UUID?
    var revealed: Bool
    var showingBack: Bool
    var activeReviewStartedAt: Date?
    var singleCardID: UUID?

    init(
        id: UUID = UUID(),
        stackID: UUID,
        startedAt: Date,
        config: SessionConfig,
        queue: ReviewQueueEnvelope,
        singleCardID: UUID? = nil
    ) {
        self.id = id
        self.stackID = stackID
        self.startedAt = startedAt
        self.lastActiveAt = startedAt
        self.activeSeconds = 0
        self.statusRaw = ReviewSessionStatus.active.rawValue
        self.configData = try? JSONEncoder().encode(config)
        self.queueData = try? JSONEncoder().encode(queue)
        self.committedPresentationIDsData = try? JSONEncoder().encode([UUID]())
        self.goodCount = 0
        self.againCount = 0
        self.currentPresentationID = queue.presentations.first?.id
        self.revealed = false
        self.showingBack = false
        self.activeReviewStartedAt = startedAt
        self.singleCardID = singleCardID
    }

    var status: ReviewSessionStatus {
        get { ReviewSessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var config: SessionConfig? {
        guard let data = configData else { return nil }
        return try? JSONDecoder().decode(SessionConfig.self, from: data)
    }

    func queue() -> ReviewQueueEnvelope {
        guard let data = queueData,
              let decoded = try? JSONDecoder().decode(ReviewQueueEnvelope.self, from: data) else {
            return ReviewQueueEnvelope(presentations: [], admittedCardIDs: [], retryCounts: [:], nextRetryAt: nil)
        }
        return decoded
    }

    func store(queue: ReviewQueueEnvelope) {
        queueData = try? JSONEncoder().encode(queue)
    }

    var committedPresentationIDs: Set<UUID> {
        guard let data = committedPresentationIDsData,
              let decoded = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return Set(decoded)
    }

    func addCommittedPresentationID(_ id: UUID) {
        var ids = committedPresentationIDs
        ids.insert(id)
        committedPresentationIDsData = try? JSONEncoder().encode(Array(ids))
    }

    func currentPresentation() -> ReviewPresentation? {
        guard let id = currentPresentationID, let queue = try? decodedQueue() else { return nil }
        return queue.presentations.first(where: { $0.id == id })
    }

    private func decodedQueue() throws -> ReviewQueueEnvelope {
        guard let data = queueData else { return ReviewQueueEnvelope(presentations: [], admittedCardIDs: [], retryCounts: [:], nextRetryAt: nil) }
        return try JSONDecoder().decode(ReviewQueueEnvelope.self, from: data)
    }

    var distinctPosition: Int {
        let queue = queue()
        guard let current = queue.presentations.first(where: { $0.id == currentPresentationID }),
              let index = queue.admittedCardIDs.firstIndex(of: current.cardID) else {
            return queue.admittedCardIDs.isEmpty ? 0 : queue.admittedCardIDs.count
        }
        return index + 1
    }

    var isSummary: Bool {
        status != .active || currentPresentationID == nil
    }
}

// MARK: - Daily admission

@Model
final class DailyAdmissionRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var scopeKey: String
    var stackID: UUID
    var dayKey: String
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    var cardIDsData: Data?

    init(
        id: UUID = UUID(),
        stackID: UUID,
        dayKey: String,
        calendarIdentifier: String,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.stackID = stackID
        self.dayKey = dayKey
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.scopeKey = "\(stackID.uuidString)|\(dayKey)"
        self.cardIDsData = try? JSONEncoder().encode([UUID]())
    }

    var cardIDs: Set<UUID> {
        get {
            guard let data = cardIDsData,
                  let decoded = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
            return Set(decoded)
        }
        set { cardIDsData = try? JSONEncoder().encode(Array(newValue)) }
    }

    func record(_ cardID: UUID) {
        var ids = cardIDs
        ids.insert(cardID)
        cardIDs = ids
    }
}

// MARK: - Schema

enum FlipabularySchema {
    static let models: [any PersistentModel.Type] = [
        VocabularyStack.self,
        VocabularyCard.self,
        VocabularyTag.self,
        CardLearningState.self,
        ReviewEvent.self,
        ReviewSession.self,
        DailyAdmissionRecord.self
    ]

    static var schema: Schema {
        Schema(models)
    }
}
