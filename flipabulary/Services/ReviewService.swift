import Foundation
import SwiftData

enum ReviewStartResult: Sendable {
    case started(UUID)
    case existing(UUID)
    case needsScope([StackDisplayModel])
    case empty(nextDueAt: Date?)
    case failure(String)
}

enum ReviewGradeResult: Equatable, Sendable {
    case advanced
    case waiting(nextRetryAt: Date)
    case completed
    case skipped(String?)
    case duplicate
    case failure(String)
}

@MainActor
final class ReviewService {
    let modelContext: ModelContext
    let preferences: PreferencesStore
    let library: LibraryService
    let maintenance: MaintenanceService
    let clock: DateProviding
    var calendar: Calendar
    let seedProvider: () -> UInt64

    var onSessionCompleted: (() -> Void)?
    /// Test hook. When set, replaces the SwiftData save step so retry/failure paths can be verified.
    var saveOverride: (() throws -> Void)?

    init(
        modelContext: ModelContext,
        preferences: PreferencesStore,
        library: LibraryService,
        maintenance: MaintenanceService,
        clock: DateProviding = SystemClock(),
        calendar: Calendar = .current,
        seedProvider: @escaping () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }
    ) {
        self.modelContext = modelContext
        self.preferences = preferences
        self.library = library
        self.maintenance = maintenance
        self.clock = clock
        self.calendar = calendar
        self.seedProvider = seedProvider
    }

    // MARK: Lookup

    func session(id: UUID) -> ReviewSession? {
        let descriptor = FetchDescriptor<ReviewSession>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    func latestActiveSession() -> ReviewSession? {
        let descriptor = FetchDescriptor<ReviewSession>()
        return (try? modelContext.fetch(descriptor))?
            .filter { $0.status == .active }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    func activeSessions() -> [ReviewSession] {
        let descriptor = FetchDescriptor<ReviewSession>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .active }
    }

    // MARK: Starting

    func requestReview(scopeID: UUID?, singleCardID: UUID? = nil) -> ReviewStartResult {
        maintenance.reconcileDecay()

        if let existing = latestActiveSession() {
            return .existing(existing.id)
        }

        if let singleCardID {
            guard let card = library.card(id: singleCardID), let stack = card.stack else {
                return .failure("This card is no longer available.")
            }
            return startSession(stack: stack, singleCard: card)
        }

        if let scopeID {
            guard let stack = library.stack(id: scopeID) else {
                return .failure("This stack is no longer available.")
            }
            let consumed = maintenance.consumedNewCardIDs(stackID: stack.id)
            let due = LibraryProjection.dueCount(
                stack: stack,
                consumed: consumed,
                globalRules: preferences.preferences.rules,
                now: clock.now,
                calendar: calendar
            )
            guard due > 0 else {
                return .empty(nextDueAt: maintenance.nextDueDate(scopeID: scopeID))
            }
            return startSession(stack: stack)
        }

        let displays = LibraryProjection.stackDisplays(
            stacks: maintenance.stacks(),
            records: maintenance.records(),
            globalRules: preferences.preferences.rules,
            now: clock.now,
            calendar: calendar
        )
        let eligible = displays.filter { $0.dueCount > 0 }
        if eligible.isEmpty {
            return .empty(nextDueAt: maintenance.nextDueDate(scopeID: nil))
        }
        if eligible.count == 1, let stack = library.stack(id: eligible[0].id) {
            return startSession(stack: stack)
        }
        return .needsScope(eligible)
    }

    private func startSession(stack: VocabularyStack, singleCard: VocabularyCard? = nil) -> ReviewStartResult {
        let now = clock.now
        let seed = seedProvider()
        let config = stack.makeSessionConfig(globalRules: preferences.preferences.rules, seed: seed)

        let admittedIDs: [UUID]
        if let singleCard {
            admittedIDs = [singleCard.id]
        } else {
            let consumed = maintenance.consumedNewCardIDs(stackID: stack.id, now: now)
            let candidates = LibraryProjection.candidates(
                stack: stack,
                globalRules: preferences.preferences.rules,
                now: now,
                calendar: calendar
            )
            let queue = LearningEngine.buildQueue(
                candidates: candidates,
                cardsPerSession: config.cardsPerSession,
                newCardsPerDay: config.newCardsPerDay,
                consumedNewCardIDs: consumed,
                shuffle: config.shuffle,
                seed: seed,
                now: now
            )
            admittedIDs = queue.admittedIDs
        }

        guard !admittedIDs.isEmpty else {
            return .empty(nextDueAt: maintenance.nextDueDate(scopeID: stack.id))
        }

        let presentations = admittedIDs.map {
            ReviewPresentation(
                id: UUID(),
                cardID: $0,
                isRetry: false,
                retryNumber: 0,
                availableAt: now,
                gradedAt: nil
            )
        }
        let queue = ReviewQueueEnvelope(
            presentations: presentations,
            admittedCardIDs: admittedIDs,
            retryCounts: [:],
            nextRetryAt: nil
        )
        let session = ReviewSession(
            stackID: stack.id,
            startedAt: now,
            config: config,
            queue: queue,
            singleCardID: singleCard?.id
        )
        modelContext.insert(session)
        do {
            try persist()
        } catch {
            modelContext.rollback()
            return .failure("The review session could not be started. \(error.localizedDescription)")
        }
        return .started(session.id)
    }

    // MARK: Current content

    func currentCard(for session: ReviewSession) -> VocabularyCard? {
        guard let presentation = session.currentPresentation() else { return nil }
        return library.card(id: presentation.cardID)
    }

    func currentPresentation(for session: ReviewSession) -> ReviewPresentation? {
        session.currentPresentation()
    }

    func reveal(_ session: ReviewSession) -> Bool {
        guard session.currentPresentationID != nil else { return false }
        session.revealed = true
        session.showingBack = true
        session.lastActiveAt = clock.now
        do {
            try persist()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    /// Changes the visible face without creating an answer event.
    func setShowingBack(_ session: ReviewSession, showing: Bool) -> Bool {
        guard session.status == .active, session.currentPresentationID != nil else { return false }
        if showing {
            session.revealed = true
        }
        session.showingBack = showing
        session.lastActiveAt = clock.now
        do {
            try persist()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    // MARK: Grading

    func grade(_ session: ReviewSession, grade: ReviewGrade) -> ReviewGradeResult {
        let now = clock.now
        guard session.status == .active else { return .completed }
        guard session.revealed, session.showingBack else { return .failure("Show the answer before rating this card.") }
        guard let presentation = session.currentPresentation() else { return .completed }
        if session.committedPresentationIDs.contains(presentation.id) {
            return .duplicate
        }
        guard let config = session.config else {
            return .failure("This session is missing its saved settings.")
        }
        guard let card = library.card(id: presentation.cardID) else {
            return skipCurrent(session, reason: "A deleted card was skipped.")
        }
        guard let stack = library.stack(id: session.stackID) else {
            _ = endSession(session, preserveSummary: true)
            return .completed
        }

        let before = card.snapshot
        let dailyRecord = maintenance.dailyRecord(stackID: session.stackID, now: now)
        if before.lifecycle == .new,
           !dailyRecord.cardIDs.contains(card.id),
           dailyRecord.cardIDs.count >= stack.newCardsPerDay {
            return skipCurrent(session, reason: "Today's new-card limit is reached. The remaining new cards stay in your library.")
        }

        let transition = LearningEngine.grade(before, grade: grade, rules: config.rules, at: now, calendar: calendar)
        if card.learningState == nil {
            let state = CardLearningState(card: card)
            modelContext.insert(state)
            card.learningState = state
        }
        guard let state = card.learningState else {
            return .failure("This card's learning state is unavailable.")
        }
        state.apply(transition.after, rulesVersion: config.rules.version)
        state.totalGrades += 1
        if before.lifecycle == .new {
            dailyRecord.record(card.id)
        }

        let event = ReviewEvent(
            presentationID: presentation.id,
            sessionID: session.id,
            cardID: card.id,
            grade: grade,
            timestamp: now,
            beforeRepeatCount: transition.before.repeatCount,
            afterRepeatCount: transition.after.repeatCount,
            beforeLifecycle: transition.before.lifecycle,
            afterLifecycle: transition.after.lifecycle,
            rulesVersion: config.rules.version,
            card: card
        )
        modelContext.insert(event)
        card.updatedAt = now

        var queue = session.queue()
        if let index = queue.presentations.firstIndex(where: { $0.id == presentation.id }) {
            queue.presentations[index].gradedAt = now
        }
        if grade == .again {
            let retries = queue.retryCounts[card.id, default: 0]
            if retries < LearningEngine.maximumRetryPresentations {
                queue.retryCounts[card.id] = retries + 1
                queue.presentations.append(
                    ReviewPresentation(
                        id: UUID(),
                        cardID: card.id,
                        isRetry: true,
                        retryNumber: retries + 1,
                        availableAt: LearningEngine.retryDueAt(now: now, rules: config.rules),
                        gradedAt: nil
                    )
                )
            }
            session.againCount += 1
        } else {
            session.goodCount += 1
        }
        session.addCommittedPresentationID(presentation.id)
        selectNext(in: session, queue: &queue, now: now)
        session.store(queue: queue)
        session.lastActiveAt = now
        session.revealed = false
        session.showingBack = false

        do {
            try persist()
        } catch {
            modelContext.rollback()
            return .failure("The rating could not be saved. Nothing was lost. \(error.localizedDescription)")
        }

        maintenance.publishSnapshot()
        if session.status == .completed {
            onSessionCompleted?()
            return .completed
        }
        if let next = queue.nextRetryAt, session.currentPresentationID == nil {
            return .waiting(nextRetryAt: next)
        }
        return .advanced
    }

    func repair(_ session: ReviewSession) {
        guard session.status == .active else { return }
        if library.stack(id: session.stackID) == nil {
            _ = endSession(session, preserveSummary: true)
            return
        }
        guard let presentation = session.currentPresentation() else {
            var queue = session.queue()
            selectNext(in: session, queue: &queue, now: clock.now)
            session.store(queue: queue)
            _ = saveSilently()
            return
        }
        if library.card(id: presentation.cardID) == nil {
            _ = skipCurrent(session, reason: "A deleted card was skipped.")
        }
    }

    private func skipCurrent(_ session: ReviewSession, reason: String?) -> ReviewGradeResult {
        var queue = session.queue()
        if let id = session.currentPresentationID,
           let index = queue.presentations.firstIndex(where: { $0.id == id }) {
            queue.presentations[index].gradedAt = clock.now
            session.addCommittedPresentationID(id)
        }
        selectNext(in: session, queue: &queue, now: clock.now)
        session.store(queue: queue)
        session.revealed = false
        session.showingBack = false
        guard saveSilently() else {
            return .failure("The session could not be updated.")
        }
        if session.status == .completed {
            onSessionCompleted?()
            return .completed
        }
        if let next = queue.nextRetryAt, session.currentPresentationID == nil {
            return .waiting(nextRetryAt: next)
        }
        return .skipped(reason)
    }

    private func selectNext(in session: ReviewSession, queue: inout ReviewQueueEnvelope, now: Date) {
        let ungraded = queue.presentations.filter { $0.gradedAt == nil }
        if let initial = ungraded.first(where: { !$0.isRetry }) {
            session.currentPresentationID = initial.id
            session.revealed = false
            session.showingBack = false
            queue.nextRetryAt = nil
            return
        }
        let dueRetries = ungraded
            .filter { $0.isRetry && $0.availableAt <= now }
            .sorted { $0.availableAt < $1.availableAt }
        if let retry = dueRetries.first {
            session.currentPresentationID = retry.id
            session.revealed = false
            session.showingBack = false
            queue.nextRetryAt = nil
            return
        }

        session.currentPresentationID = nil
        session.revealed = false
        session.showingBack = false
        let futureRetries = ungraded.filter(\.isRetry).map(\.availableAt)
        queue.nextRetryAt = futureRetries.min()
        if futureRetries.isEmpty {
            session.status = .completed
            session.endedAt = now
            pauseActive(session, now: now)
        }
    }

    // MARK: Waiting and ending

    @discardableResult
    func advanceIfPossible(_ session: ReviewSession) -> Bool {
        guard session.status == .active, session.currentPresentationID == nil else { return false }
        var queue = session.queue()
        selectNext(in: session, queue: &queue, now: clock.now)
        session.store(queue: queue)
        guard saveSilently() else { return false }
        if session.status == .completed {
            onSessionCompleted?()
        }
        return session.currentPresentationID != nil || session.status == .completed
    }

    @discardableResult
    func endSession(_ session: ReviewSession, preserveSummary: Bool = true) -> Bool {
        let now = clock.now
        pauseActive(session, now: now)
        session.status = .completed
        session.endedAt = now
        session.currentPresentationID = nil
        session.revealed = false
        session.showingBack = false
        session.lastActiveAt = now
        do {
            try persist()
        } catch {
            modelContext.rollback()
            return false
        }
        maintenance.publishSnapshot()
        onSessionCompleted?()
        return true
    }

    func pause(_ session: ReviewSession) {
        guard session.status == .active else { return }
        pauseActive(session, now: clock.now)
        session.lastActiveAt = clock.now
        _ = saveSilently()
    }

    func resume(_ session: ReviewSession) {
        guard session.status == .active, session.activeReviewStartedAt == nil else { return }
        session.activeReviewStartedAt = clock.now
        _ = saveSilently()
    }

    private func pauseActive(_ session: ReviewSession, now: Date) {
        if let started = session.activeReviewStartedAt {
            session.activeSeconds += max(0, now.timeIntervalSince(started))
            session.activeReviewStartedAt = nil
        }
    }

    @discardableResult
    private func saveSilently() -> Bool {
        do {
            try persist()
            return true
        } catch {
            modelContext.rollback()
            return false
        }
    }

    private func persist() throws {
        if let saveOverride {
            try saveOverride()
        } else {
            try modelContext.save()
        }
    }

    // MARK: Summary helpers

    func totalReviewed(_ session: ReviewSession) -> Int {
        session.goodCount + session.againCount
    }

    func distinctCount(_ session: ReviewSession) -> Int {
        session.queue().admittedCardIDs.count
    }

    func elapsedSeconds(_ session: ReviewSession, at now: Date) -> Double {
        var total = session.activeSeconds
        if let started = session.activeReviewStartedAt {
            total += max(0, now.timeIntervalSince(started))
        }
        return total
    }
}
