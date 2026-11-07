import Foundation
import SwiftData

enum LibraryProjection {
    private struct StackStats {
        var candidates: [LearningEngine.QueueCandidate] = []
        var saved = 0
        var learned = 0
        var learning = 0
        var new = 0
    }

    static func displayModels(
        stacks: [VocabularyStack],
        globalRules: LearningRules,
        recentGradesByCard: [UUID: [CardHistoryItem]]? = nil
    ) -> [CardDisplayModel] {
        displayModels(
            cards: stacks.flatMap(\.cards),
            stacks: stacks,
            globalRules: globalRules,
            recentGradesByCard: recentGradesByCard
        )
    }

    static func displayModels(
        cards: [VocabularyCard],
        stacks: [VocabularyStack],
        globalRules: LearningRules,
        recentGradesByCard: [UUID: [CardHistoryItem]]? = nil
    ) -> [CardDisplayModel] {
        var rulesByStack: [UUID: LearningRules] = [:]
        rulesByStack.reserveCapacity(stacks.count)
        for stack in stacks {
            rulesByStack[stack.id] = stack.effectiveRules(global: globalRules)
        }
        var result: [CardDisplayModel] = []
        result.reserveCapacity(cards.count)
        for card in cards {
            guard let stack = card.stack else { continue }
            let rules = rulesByStack[stack.id] ?? stack.effectiveRules(global: globalRules)
            let recent = recentGradesByCard.map { $0[card.id] ?? [] }
            result.append(displayModel(card: card, stack: stack, rules: rules, recentGrades: recent))
        }
        return result
    }

    static func displayModel(
        card: VocabularyCard,
        stack: VocabularyStack,
        rules: LearningRules,
        recentGrades: [CardHistoryItem]? = nil
    ) -> CardDisplayModel {
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
            recentGrades: recentGrades ?? LibraryQuery.recentGrades(from: card.reviewEvents)
        )
    }

    static func candidates(
        stack: VocabularyStack,
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> [LearningEngine.QueueCandidate] {
        stats(stack: stack, globalRules: globalRules, now: now, calendar: calendar).candidates
    }

    static func dueCount(
        stack: VocabularyStack,
        consumed: Set<UUID>,
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let stats = stats(stack: stack, globalRules: globalRules, now: now, calendar: calendar)
        return LearningEngine.actionableDueCount(
            candidates: stats.candidates,
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
        dueCount(
            scopeID: scopeID,
            stacks: stacks,
            cards: stacks.flatMap(\.cards),
            records: records,
            globalRules: globalRules,
            now: now,
            calendar: calendar
        )
    }

    static func dueCount(
        scopeID: UUID?,
        stacks: [VocabularyStack],
        cards: [VocabularyCard],
        records: [DailyAdmissionRecord],
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let recordsByStack = recordsByStackForToday(records, now: now, calendar: calendar)
        let cardsByStack = cardsByStack(cards)
        var total = 0
        for stack in stacks where scopeID == nil || stack.id == scopeID {
            let rules = stack.effectiveRules(global: globalRules)
            let stats = stats(
                cards: cardsByStack[stack.id] ?? [],
                rules: rules,
                now: now,
                calendar: calendar
            )
            total += LearningEngine.actionableDueCount(
                candidates: stats.candidates,
                newCardsPerDay: stack.newCardsPerDay,
                consumedNewCardIDs: recordsByStack[stack.id]?.cardIDs ?? [],
                now: now
            )
        }
        return total
    }

    static func stackDisplays(
        stacks: [VocabularyStack],
        records: [DailyAdmissionRecord],
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> [StackDisplayModel] {
        stackDisplays(
            stacks: stacks,
            cards: stacks.flatMap(\.cards),
            records: records,
            globalRules: globalRules,
            now: now,
            calendar: calendar
        )
    }

    static func stackDisplays(
        stacks: [VocabularyStack],
        cards: [VocabularyCard],
        records: [DailyAdmissionRecord],
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> [StackDisplayModel] {
        let recordsByStack = recordsByStackForToday(records, now: now, calendar: calendar)
        let cardsByStack = cardsByStack(cards)
        return stacks.map { stack in
            let rules = stack.effectiveRules(global: globalRules)
            let stats = stats(
                cards: cardsByStack[stack.id] ?? [],
                rules: rules,
                now: now,
                calendar: calendar
            )
            let due = LearningEngine.actionableDueCount(
                candidates: stats.candidates,
                newCardsPerDay: stack.newCardsPerDay,
                consumedNewCardIDs: recordsByStack[stack.id]?.cardIDs ?? [],
                now: now
            )
            return StackDisplayModel(
                id: stack.id,
                name: stack.name,
                savedCount: stats.saved,
                dueCount: due,
                learnedCount: stats.learned
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
        widgetSnapshot(
            stacks: stacks,
            cards: stacks.flatMap(\.cards),
            records: records,
            preferences: preferences,
            now: now,
            calendar: calendar
        )
    }

    static func widgetSnapshot(
        stacks: [VocabularyStack],
        cards: [VocabularyCard],
        records: [DailyAdmissionRecord],
        preferences: AppPreferences,
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot {
        let recordsByStack = recordsByStackForToday(records, now: now, calendar: calendar)
        var cardsByStack: [UUID: [VocabularyCard]] = [:]
        cardsByStack.reserveCapacity(stacks.count)
        for card in cards {
            guard let stackID = card.stack?.id else { continue }
            cardsByStack[stackID, default: []].append(card)
        }
        let stackSnapshots = stacks.map { stack -> WidgetStackSnapshot in
            let rules = stack.effectiveRules(global: preferences.rules)
            let sortedCards = (cardsByStack[stack.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            var candidates: [LearningEngine.QueueCandidate] = []
            candidates.reserveCapacity(sortedCards.count)
            var cards: [WidgetCardSnapshot] = []
            cards.reserveCapacity(sortedCards.count)
            var learned = 0
            var learning = 0
            var new = 0
            var nextDue: Date?

            for card in sortedCards {
                let state = card.learningState?.snapshot ?? .fresh
                let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
                switch reconciled.lifecycle {
                case .learned: learned += 1
                case .learning: learning += 1
                case .new: new += 1
                }
                if reconciled.lifecycle != .new, let due = reconciled.nextDueAt {
                    nextDue = nextDue.map { min($0, due) } ?? due
                }
                candidates.append(
                    LearningEngine.QueueCandidate(
                        id: card.id,
                        lifecycle: reconciled.lifecycle,
                        nextDueAt: reconciled.nextDueAt,
                        createdAt: card.createdAt,
                        appliedMilestoneCount: reconciled.appliedMilestones.count
                    )
                )
                cards.append(
                    WidgetCardSnapshot(
                        id: card.id,
                        word: card.word,
                        translation: card.translation,
                        lifecycle: reconciled.lifecycle.rawValue,
                        repeatCount: reconciled.repeatCount,
                        threshold: rules.correctThreshold,
                        dueAt: reconciled.nextDueAt,
                        createdAt: card.createdAt
                    )
                )
            }

            let due = LearningEngine.actionableDueCount(
                candidates: candidates,
                newCardsPerDay: stack.newCardsPerDay,
                consumedNewCardIDs: recordsByStack[stack.id]?.cardIDs ?? [],
                now: now
            )
            return WidgetStackSnapshot(
                id: stack.id,
                name: stack.name,
                savedCount: sortedCards.count,
                dueCount: due,
                learnedCount: learned,
                learningCount: learning,
                newCount: new,
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

    private static func stats(
        stack: VocabularyStack,
        globalRules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> StackStats {
        stats(
            cards: stack.cards,
            rules: stack.effectiveRules(global: globalRules),
            now: now,
            calendar: calendar
        )
    }

    private static func stats(
        cards: [VocabularyCard],
        rules: LearningRules,
        now: Date,
        calendar: Calendar
    ) -> StackStats {
        var result = StackStats()
        result.candidates.reserveCapacity(cards.count)
        result.saved = cards.count
        for card in cards {
            let state = card.learningState?.snapshot ?? .fresh
            let reconciled = LearningEngine.reconcileDecay(state, rules: rules, at: now, calendar: calendar).after
            switch reconciled.lifecycle {
            case .learned: result.learned += 1
            case .learning: result.learning += 1
            case .new: result.new += 1
            }
            result.candidates.append(
                LearningEngine.QueueCandidate(
                    id: card.id,
                    lifecycle: reconciled.lifecycle,
                    nextDueAt: reconciled.nextDueAt,
                    createdAt: card.createdAt,
                    appliedMilestoneCount: reconciled.appliedMilestones.count
                )
            )
        }
        return result
    }

    private static func cardsByStack(_ cards: [VocabularyCard]) -> [UUID: [VocabularyCard]] {
        var result: [UUID: [VocabularyCard]] = [:]
        for card in cards {
            guard let stackID = card.stack?.id else { continue }
            result[stackID, default: []].append(card)
        }
        return result
    }

    private static func recordsByStackForToday(
        _ records: [DailyAdmissionRecord],
        now: Date,
        calendar: Calendar
    ) -> [UUID: DailyAdmissionRecord] {
        let todayKey = CalendarTools.dayKey(for: now, calendar: calendar)
        var result: [UUID: DailyAdmissionRecord] = [:]
        result.reserveCapacity(records.count)
        for record in records where record.dayKey == todayKey {
            result[record.stackID] = record
        }
        return result
    }
}
