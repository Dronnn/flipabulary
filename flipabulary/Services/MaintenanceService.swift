import Foundation
import SwiftData
import WidgetKit

protocol WidgetReloading: Sendable {
    func reloadAll()
}

struct SystemWidgetReloader: WidgetReloading {
    func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct NoopWidgetReloader: WidgetReloading {
    func reloadAll() {}
}

@MainActor
final class MaintenanceService {
    let modelContext: ModelContext
    let preferences: PreferencesStore
    let clock: DateProviding
    var calendar: Calendar
    let snapshotStore: WidgetSnapshotStore
    let widgetReloader: WidgetReloading

    var lastError: String?
    var onSnapshotPublished: (() -> Void)?

    init(
        modelContext: ModelContext,
        preferences: PreferencesStore,
        clock: DateProviding = SystemClock(),
        calendar: Calendar = .current,
        snapshotStore: WidgetSnapshotStore = .shared,
        widgetReloader: WidgetReloading = SystemWidgetReloader()
    ) {
        self.modelContext = modelContext
        self.preferences = preferences
        self.clock = clock
        self.calendar = calendar
        self.snapshotStore = snapshotStore
        self.widgetReloader = widgetReloader
    }

    func stacks() -> [VocabularyStack] {
        (try? modelContext.fetch(FetchDescriptor<VocabularyStack>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func records() -> [DailyAdmissionRecord] {
        (try? modelContext.fetch(FetchDescriptor<DailyAdmissionRecord>())) ?? []
    }

    func cards() -> [VocabularyCard] {
        (try? modelContext.fetch(FetchDescriptor<VocabularyCard>())) ?? []
    }

    func cardsForList() -> [VocabularyCard] {
        var descriptor = FetchDescriptor<VocabularyCard>()
        descriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState, \.tags]
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func refresh() {
        let stacks = stacks()
        reconcileDecay(stacks: stacks)
        promoteWhereRulesRequire(stacks: stacks)
        publishSnapshot(stacks: stacks)
    }

    func reconcileDecay() {
        reconcileDecay(stacks: stacks())
    }

    private func reconcileDecay(stacks: [VocabularyStack]) {
        let now = clock.now
        guard !stacks.isEmpty else { return }
        var changed = false
        for stack in stacks {
            let rules = stack.effectiveRules(global: preferences.preferences.rules)
            for card in stack.cards {
                guard let state = card.learningState, state.lifecycle == .learned else { continue }
                let transition = LearningEngine.reconcileDecay(
                    state.snapshot,
                    rules: rules,
                    at: now,
                    calendar: calendar
                )
                if transition.after != transition.before {
                    state.apply(transition.after, rulesVersion: rules.version)
                    changed = true
                }
            }
        }
        if changed {
            save()
            publishSnapshot()
        }
    }

    func promoteWhereRulesRequire() {
        promoteWhereRulesRequire(stacks: stacks())
    }

    private func promoteWhereRulesRequire(stacks: [VocabularyStack]) {
        var changed = false
        for stack in stacks {
            let rules = stack.effectiveRules(global: preferences.preferences.rules)
            for card in stack.cards {
                guard let state = card.learningState else { continue }
                if state.lifecycle == .learning,
                   !state.mistakeReturn,
                   state.repeatCount >= rules.correctThreshold {
                    var snapshot = state.snapshot
                    snapshot.lifecycle = .learned
                    snapshot.learnedAnchor = state.lastGradedAt ?? clock.now
                    snapshot.appliedMilestones = []
                    snapshot.nextDueAt = LearningEngine.milestoneDate(
                        index: 0,
                        anchor: snapshot.learnedAnchor ?? clock.now,
                        calendar: calendar
                    )
                    snapshot.mistakeReturn = false
                    state.apply(snapshot, rulesVersion: rules.version)
                    changed = true
                }
            }
        }
        if changed {
            save()
            publishSnapshot()
        }
    }

    func reanchorDecay(scopeID: UUID?, includeCustomRules: Bool = false) {
        let stacks = stacks().filter { stack in
            if let scopeID { return stack.id == scopeID }
            return includeCustomRules || stack.customRulesData == nil
        }
        let now = clock.now
        var changed = false
        for stack in stacks {
            let rules = stack.effectiveRules(global: preferences.preferences.rules)
            guard rules.autoDecrease else { continue }
            for card in stack.cards {
                guard let state = card.learningState, state.lifecycle == .learned else { continue }
                let updated = LearningEngine.reanchorForEnabledDecay(state.snapshot, at: now, calendar: calendar)
                state.apply(updated, rulesVersion: rules.version)
                changed = true
            }
        }
        if changed {
            save()
            publishSnapshot()
        }
    }

    func dailyRecord(stackID: UUID, now: Date? = nil) -> DailyAdmissionRecord {
        let date = now ?? clock.now
        let key = CalendarTools.dayKey(for: date, calendar: calendar)
        let scopeKey = "\(stackID.uuidString)|\(key)"
        let descriptor = FetchDescriptor<DailyAdmissionRecord>(predicate: #Predicate { $0.scopeKey == scopeKey })
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let record = DailyAdmissionRecord(
            stackID: stackID,
            dayKey: key,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        modelContext.insert(record)
        return record
    }

    func consumedNewCardIDs(stackID: UUID, now: Date? = nil) -> Set<UUID> {
        let date = now ?? clock.now
        let key = CalendarTools.dayKey(for: date, calendar: calendar)
        let scopeKey = "\(stackID.uuidString)|\(key)"
        let descriptor = FetchDescriptor<DailyAdmissionRecord>(predicate: #Predicate { $0.scopeKey == scopeKey })
        return (try? modelContext.fetch(descriptor).first)?.cardIDs ?? []
    }

    func remainingNewAllowance(stack: VocabularyStack, now: Date? = nil) -> Int {
        let consumed = consumedNewCardIDs(stackID: stack.id, now: now).count
        return max(0, stack.newCardsPerDay - consumed)
    }

    func publishSnapshot() {
        publishSnapshot(stacks: stacks())
    }

    private func publishSnapshot(stacks: [VocabularyStack]) {
        let snapshot = LibraryProjection.widgetSnapshot(
            stacks: stacks,
            cards: cardsForList(),
            records: records(),
            preferences: preferences.preferences,
            now: clock.now,
            calendar: calendar
        )
        do {
            try snapshotStore.save(snapshot)
            widgetReloader.reloadAll()
            lastError = nil
            onSnapshotPublished?()
        } catch {
            lastError = "Widget data could not be published: \(error.localizedDescription)"
        }
    }

    func nextDueDate(scopeID: UUID?) -> Date? {
        let stacks = stacks().filter { scopeID == nil || $0.id == scopeID }
        let now = clock.now
        var earliest: Date?
        for stack in stacks {
            let rules = stack.effectiveRules(global: preferences.preferences.rules)
            for card in stack.cards {
                let state = card.learningState?.snapshot ?? .fresh
                let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
                guard reconciled.lifecycle == .learning || reconciled.lifecycle == .learned,
                      let due = reconciled.nextDueAt,
                      due > now else { continue }
                earliest = earliest.map { min($0, due) } ?? due
            }
        }
        return earliest
    }

    @discardableResult
    func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            lastError = "Changes could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
