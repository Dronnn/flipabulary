import Foundation
import SwiftData

enum LibraryProjection {
    static func displayModels(
        stacks: [VocabularyStack],
        globalRules: LearningRules
    ) -> [CardDisplayModel] {
        var result: [CardDisplayModel] = []
        for stack in stacks {
            let rules = stack.effectiveRules(global: globalRules)
            for card in stack.cards {
                result.append(displayModel(card: card, stack: stack, rules: rules))
            }
        }
        return result
    }

    static func displayModel(card: VocabularyCard, stack: VocabularyStack, rules: LearningRules) -> CardDisplayModel {
        let state = card.learningState
        return CardDisplayModel(
            id: card.id,
            word: card.word,
            translation: card.translation,
            sourceExample: card.sourceExample,
            translatedExample: card.translatedExample,
            phonetic: card.phonetic,
            partOfSpeech: card.partOfSpeech,
            stackID: stack.id,
            stackName: stack.name,
            tagNames: card.tags.map(\.name).sorted(),
            lifecycle: state?.lifecycle ?? .new,
            repeatCount: state?.repeatCount ?? 0,
            threshold: rules.correctThreshold,
            nextDueAt: state?.nextDueAt,
            createdAt: card.createdAt,
            recentGrades: LibraryQuery.recentGrades(from: card.reviewEvents)
        )
    }

    static func candidates(
        stack: VocabularyStack,
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> [LearningEngine.QueueCandidate] {
        let rules = stack.effectiveRules(global: globalRules)
        return stack.cards.map { card in
            let state = card.learningState?.snapshot ?? .fresh
            let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
            return LearningEngine.QueueCandidate(
                id: card.id,
                lifecycle: reconciled.lifecycle,
                nextDueAt: reconciled.nextDueAt,
                createdAt: card.createdAt,
                appliedMilestoneCount: reconciled.appliedMilestones.count
            )
        }
    }

    static func dueCount(
        stack: VocabularyStack,
        consumed: Set<UUID>,
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let candidates = candidates(stack: stack, globalRules: globalRules, now: now, calendar: calendar)
        return LearningEngine.actionableDueCount(
            candidates: candidates,
            newCardsPerDay: stack.newCardsPerDay,
            consumedNewCardIDs: consumed,
            now: now
        )
    }

    static func dueCount(
        scopeID: UUID?,
        stacks: [VocabularyStack],
        records: [DailyAdmissionRecord],
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> Int {
        stacks
            .filter { scopeID == nil || $0.id == scopeID }
            .reduce(0) { total, stack in
                let record = records.first(where: { $0.stackID == stack.id && recordMatchesToday($0, now: now, calendar: calendar) })
                return total + dueCount(
                    stack: stack,
                    consumed: record?.cardIDs ?? [],
                    globalRules: globalRules,
                    now: now,
                    calendar: calendar
                )
            }
    }

    static func stackDisplays(
        stacks: [VocabularyStack],
        records: [DailyAdmissionRecord],
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> [StackDisplayModel] {
        stacks.map { stack in
            let record = records.first(where: { $0.stackID == stack.id && recordMatchesToday($0, now: now, calendar: calendar) })
            let due = dueCount(
                stack: stack,
                consumed: record?.cardIDs ?? [],
                globalRules: globalRules,
                now: now,
                calendar: calendar
            )
            return StackDisplayModel(
                id: stack.id,
                name: stack.name,
                savedCount: stack.cards.count,
                dueCount: due,
                learnedCount: stack.cards.filter { $0.learningState?.lifecycle == .learned }.count
            )
        }
    }

    static func recordMatchesToday(_ record: DailyAdmissionRecord, now: Date, calendar: Calendar) -> Bool {
        record.dayKey == CalendarTools.dayKey(for: now, calendar: calendar)
    }

    static func widgetSnapshot(
        stacks: [VocabularyStack],
        records: [DailyAdmissionRecord],
        preferences: AppPreferences,
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot {
        let stackSnapshots = stacks.map { stack -> WidgetStackSnapshot in
            let rules = stack.effectiveRules(global: preferences.rules)
            let record = records.first(where: { $0.stackID == stack.id && recordMatchesToday($0, now: now, calendar: calendar) })
            let candidates = candidates(stack: stack, globalRules: preferences.rules, now: now, calendar: calendar)
            let due = LearningEngine.actionableDueCount(
                candidates: candidates,
                newCardsPerDay: stack.newCardsPerDay,
                consumedNewCardIDs: record?.cardIDs ?? [],
                now: now
            )
            let cards = stack.cards
                .sorted { $0.createdAt < $1.createdAt }
                .map { card in
                    let state = card.learningState?.snapshot ?? .fresh
                    let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
                    return WidgetCardSnapshot(
                        id: card.id,
                        word: card.word,
                        translation: card.translation,
                        lifecycle: reconciled.lifecycle.rawValue,
                        repeatCount: reconciled.repeatCount,
                        threshold: rules.correctThreshold,
                        dueAt: reconciled.nextDueAt,
                        createdAt: card.createdAt
                    )
                }
            let nextDue = stack.cards.compactMap { card -> Date? in
                let state = card.learningState?.snapshot ?? .fresh
                let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
                guard reconciled.lifecycle != .new else { return nil }
                return reconciled.nextDueAt
            }.min()
            return WidgetStackSnapshot(
                id: stack.id,
                name: stack.name,
                savedCount: stack.cards.count,
                dueCount: due,
                learnedCount: stack.cards.filter { card in
                    let state = card.learningState?.snapshot ?? .fresh
                    return LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after.lifecycle == .learned
                }.count,
                learningCount: stack.cards.filter { card in
                    let state = card.learningState?.snapshot ?? .fresh
                    let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
                    return reconciled.lifecycle == .learning
                }.count,
                newCount: stack.cards.filter { card in
                    let state = card.learningState?.snapshot ?? .fresh
                    return LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after.lifecycle == .new
                }.count,
                cards: cards,
                nextDueAt: nextDue
            )
        }
        let allCards = stackSnapshots.flatMap(\.cards)
        let cardsByID = Dictionary(allCards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wordSetSnapshots = preferences.widgetWordSets.map { set -> WidgetWordSetSnapshot in
            var seen = Set<UUID>()
            let cards = set.cardIDs.compactMap { id -> WidgetCardSnapshot? in
                guard seen.insert(id).inserted else { return nil }
                return cardsByID[id]
            }
            let activeCards = cards.filter { $0.lifecycle != "learned" }
            let due = activeCards.filter { card in
                guard let dueAt = card.dueAt else { return true }
                return dueAt <= now
            }.count
            return WidgetWordSetSnapshot(
                id: set.id,
                name: set.name,
                cards: cards,
                savedCount: cards.count,
                dueCount: due,
                learnedCount: cards.filter { $0.lifecycle == "learned" }.count,
                learningCount: cards.filter { $0.lifecycle == "learning" }.count,
                newCount: cards.filter { $0.lifecycle == "new" }.count,
                nextDueAt: activeCards.compactMap(\.dueAt).min()
            )
        }
        let validDefault = preferences.widgetDefaults.stackID ?? preferences.selectedStackID
        let validDefaultSet = preferences.widgetDefaults.wordSetID.flatMap { id in
            wordSetSnapshots.contains(where: { $0.id == id }) ? id : nil
        }
        return WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: now,
            stacks: stackSnapshots,
            defaultStackID: stackSnapshots.contains(where: { $0.id == validDefault }) ? validDefault : nil,
            defaultSort: preferences.widgetDefaults.sort,
            defaultShowTranslations: preferences.widgetDefaults.showTranslations,
            languageCode: preferences.language.flatMap { $0.isSystem ? nil : $0.rawValue },
            wordSets: wordSetSnapshots,
            defaultWordSetID: validDefaultSet
        )
    }
}
