import Foundation
import SwiftData

extension LibraryService {
    func wordStatistics(cardID: UUID, now: Date, calendar: Calendar) async -> WordStatistics? {
        let container = modelContext.container
        let globalRules = preferences.preferences.rules
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let targetID = cardID
            var cardDescriptor = FetchDescriptor<VocabularyCard>(predicate: #Predicate { $0.id == targetID })
            cardDescriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState]
            guard let card = try? context.fetch(cardDescriptor).first else { return nil }

            let events = (try? context.fetch(
                FetchDescriptor<ReviewEvent>(
                    predicate: #Predicate { $0.cardID == targetID },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
            )) ?? []

            var good = 0
            var again = 0
            var front = 0.0
            var back = 0.0
            var timedGrades = 0
            var history: [WordReviewHistoryItem] = []
            history.reserveCapacity(min(events.count, 12))
            for event in events {
                switch event.grade {
                case .good: good += 1
                case .again: again += 1
                }
                let frontSeconds = event.frontSeconds ?? 0
                let backSeconds = event.backSeconds ?? 0
                front += frontSeconds
                back += backSeconds
                if frontSeconds + backSeconds > 0 { timedGrades += 1 }
                if history.count < 12 {
                    history.append(
                        WordReviewHistoryItem(
                            id: event.id,
                            date: event.timestamp,
                            grade: event.grade,
                            frontSeconds: frontSeconds,
                            backSeconds: backSeconds
                        )
                    )
                }
            }

            let state = card.learningState
            let rules = card.stack?.effectiveRules(global: globalRules) ?? globalRules
            let mastered = state?.lifecycle == .learned
                && (state?.appliedMilestones.count ?? 0) >= LearningEngine.decayMilestones.count
                && state?.nextDueAt == nil
            let automaticDifficult = events.prefix(5).filter { $0.grade == .again }.count >= 2
            return WordStatistics(
                cardID: card.id,
                word: card.word,
                translation: card.translation,
                lifecycle: state?.lifecycle ?? .new,
                repeatCount: state?.repeatCount ?? 0,
                threshold: rules.correctThreshold,
                totalGrades: events.count,
                timedGrades: timedGrades,
                goodCount: good,
                againCount: again,
                frontSeconds: front,
                backSeconds: back,
                lastReviewedAt: events.first?.timestamp,
                nextDueAt: state?.nextDueAt,
                isFullyMastered: mastered,
                isDifficult: card.difficultOverride ?? automaticDifficult,
                history: history
            )
        }.value
    }

    func libraryStatistics(
        stackID: UUID?,
        rangeDays: Int,
        now: Date,
        calendar: Calendar,
        liveAppUsage: AppUsageInterval?
    ) async -> LibraryStatistics {
        let container = modelContext.container
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let stacks = ((try? context.fetch(FetchDescriptor<VocabularyStack>())) ?? [])
                .filter { stackID == nil || $0.id == stackID }
            let stackIDs = Set(stacks.map(\.id))
            var cardDescriptor = FetchDescriptor<VocabularyCard>()
            cardDescriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState]
            let cards = ((try? context.fetch(cardDescriptor)) ?? [])
                .filter { card in
                    guard let cardStackID = card.stack?.id else { return false }
                    return stackID == nil || cardStackID == stackID
                }
            let sessions = (try? context.fetch(FetchDescriptor<ReviewSession>())) ?? []
            let sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let events = (try? context.fetch(
                FetchDescriptor<ReviewEvent>(sortBy: [SortDescriptor(\.timestamp)])
            )) ?? []
            let usageRecords = (try? context.fetch(FetchDescriptor<AppUsageRecord>())) ?? []

            let range = min(max(rangeDays, 1), 366)
            let today = calendar.startOfDay(for: now)
            let rangeStart = calendar.date(byAdding: .day, value: -(range - 1), to: today) ?? today
            var dayPoints: [String: DayStatistics] = [:]
            for offset in stride(from: range - 1, through: 0, by: -1) {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = CalendarTools.dayKey(for: date, calendar: calendar)
                dayPoints[key] = DayStatistics(date: date, dayKey: key)
            }
            let rangeDayKeys = Set(dayPoints.keys)

            var totalAppSeconds = 0.0
            if stackID == nil {
                for record in usageRecords where rangeDayKeys.contains(record.dayKey) {
                    let seconds = max(0, record.seconds)
                    totalAppSeconds += seconds
                    if var point = dayPoints[record.dayKey] {
                        point.appSeconds += seconds
                        dayPoints[record.dayKey] = point
                    }
                }
                if let liveAppUsage {
                    let liveEnd = min(liveAppUsage.end, now)
                    if liveEnd > liveAppUsage.start {
                        let segments = AppUsageDaySplitter.split(
                            from: liveAppUsage.start,
                            to: liveEnd,
                            calendar: calendar
                        )
                        for segment in segments where rangeDayKeys.contains(segment.dayKey) {
                            totalAppSeconds += segment.seconds
                            if var point = dayPoints[segment.dayKey] {
                                point.appSeconds += segment.seconds
                                dayPoints[segment.dayKey] = point
                            }
                        }
                    }
                }
            }

            var cardStackByID: [UUID: UUID] = [:]
            cardStackByID.reserveCapacity(cards.count)
            for card in cards {
                if let stackID = card.stack?.id {
                    cardStackByID[card.id] = stackID
                }
            }

            var stackStats: [UUID: StackStatistics] = [:]
            for stack in stacks {
                stackStats[stack.id] = StackStatistics(
                    id: stack.id,
                    name: stack.name,
                    saved: 0,
                    learned: 0,
                    mastered: 0,
                    reviews: 0,
                    good: 0,
                    again: 0,
                    reviewSeconds: 0,
                    frontSeconds: 0,
                    backSeconds: 0,
                    activeSessionSeconds: 0,
                    lastReviewedAt: nil
                )
            }

            for card in cards {
                guard let id = card.stack?.id, var stats = stackStats[id] else { continue }
                stats.saved += 1
                let state = card.learningState
                if state?.lifecycle == .learned {
                    stats.learned += 1
                    if (state?.appliedMilestones.count ?? 0) >= LearningEngine.decayMilestones.count,
                       state?.nextDueAt == nil {
                        stats.mastered += 1
                    }
                }
                stackStats[id] = stats
            }

            var totalGood = 0
            var totalAgain = 0
            var totalReviewSeconds = 0.0
            for event in events where event.timestamp >= rangeStart && event.timestamp <= now {
                let eventStackID = sessionsByID[event.sessionID]?.stackID ?? cardStackByID[event.cardID]
                if let stackID, eventStackID != stackID { continue }

                let front = event.frontSeconds ?? 0
                let back = event.backSeconds ?? 0
                switch event.grade {
                case .good: totalGood += 1
                case .again: totalAgain += 1
                }
                totalReviewSeconds += front + back

                if let eventStackID, stackIDs.contains(eventStackID),
                   var stats = stackStats[eventStackID] {
                    stats.reviews += 1
                    if event.grade == .good { stats.good += 1 } else { stats.again += 1 }
                    stats.reviewSeconds += front + back
                    stats.frontSeconds += front
                    stats.backSeconds += back
                    if stats.lastReviewedAt.map({ $0 < event.timestamp }) ?? true {
                        stats.lastReviewedAt = event.timestamp
                    }
                    stackStats[eventStackID] = stats
                }

                let key = CalendarTools.dayKey(for: event.timestamp, calendar: calendar)
                if var point = dayPoints[key] {
                    if event.grade == .good { point.good += 1 } else { point.again += 1 }
                    point.reviewSeconds += front + back
                    dayPoints[key] = point
                }
            }

            for session in sessions where session.startedAt >= rangeStart && session.startedAt <= now {
                if let stackID, session.stackID != stackID { continue }
                guard var stats = stackStats[session.stackID] else { continue }
                stats.activeSessionSeconds += session.activeSeconds
                stackStats[session.stackID] = stats
            }

            let saved = cards.count
            let learned = cards.reduce(0) { total, card in
                total + (card.learningState?.lifecycle == .learned ? 1 : 0)
            }
            let mastered = cards.reduce(0) { total, card in
                guard let state = card.learningState,
                      state.lifecycle == .learned,
                      state.appliedMilestones.count >= LearningEngine.decayMilestones.count,
                      state.nextDueAt == nil else { return total }
                return total + 1
            }
            let days = dayPoints.values.sorted { $0.date < $1.date }
            let stacksOut = stackStats.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return LibraryStatistics(
                days: days,
                stacks: stacksOut,
                totalAppSeconds: totalAppSeconds,
                totalReviewSeconds: totalReviewSeconds,
                totalReviews: totalGood + totalAgain,
                totalGood: totalGood,
                totalAgain: totalAgain,
                saved: saved,
                learned: learned,
                mastered: mastered
            )
        }.value
    }

    func setCorrectStreak(cardID: UUID, value: Int) -> Result<Void, LibraryWriteError> {
        guard let card = card(id: cardID), let stack = card.stack else {
            return .failure(.missingStack)
        }
        let rules = stack.effectiveRules(global: preferences.preferences.rules)
        let state: CardLearningState
        if let existing = card.learningState {
            state = existing
        } else {
            let created = CardLearningState(card: card)
            modelContext.insert(created)
            card.learningState = created
            state = created
        }

        let count = min(max(value, 0), 100)
        state.repeatCount = count
        if count >= rules.correctThreshold {
            if state.lifecycle != .learned {
                state.lifecycle = .learned
                state.learnedAnchor = clock.now
                state.appliedMilestones = []
                state.nextDueAt = LearningEngine.milestoneDate(
                    index: 0,
                    anchor: clock.now,
                    calendar: maintenance.calendar
                )
            }
            state.mistakeReturn = false
        } else if state.lifecycle == .learned {
            state.lifecycle = .learning
            state.learnedAnchor = nil
            state.appliedMilestones = []
            state.nextDueAt = clock.now
            state.mistakeReturn = false
        } else if state.lifecycle == .new, count > 0 {
            state.lifecycle = .learning
            state.nextDueAt = clock.now
        }
        card.updatedAt = clock.now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The learning state could not be saved. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }

    func setDifficult(cardID: UUID, isDifficult: Bool) -> Result<Void, LibraryWriteError> {
        guard let card = card(id: cardID) else {
            return .failure(.missingStack)
        }
        card.difficultOverride = isDifficult
        card.updatedAt = clock.now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The word could not be updated. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }

    func setFullyLearned(cardID: UUID, mastered: Bool) -> Result<Void, LibraryWriteError> {
        guard let card = card(id: cardID), let stack = card.stack else {
            return .failure(.missingStack)
        }
        let rules = stack.effectiveRules(global: preferences.preferences.rules)
        let state: CardLearningState
        if let existing = card.learningState {
            state = existing
        } else {
            let created = CardLearningState(card: card)
            modelContext.insert(created)
            card.learningState = created
            state = created
        }

        if mastered {
            state.repeatCount = max(state.repeatCount, rules.correctThreshold)
            state.lifecycle = .learned
            state.learnedAnchor = state.learnedAnchor ?? clock.now
            state.appliedMilestones = Set(LearningEngine.decayMilestones.map(\.index))
            state.nextDueAt = nil
            state.mistakeReturn = false
        } else {
            state.repeatCount = min(state.repeatCount, max(0, rules.correctThreshold - 1))
            state.lifecycle = .learning
            state.learnedAnchor = nil
            state.appliedMilestones = []
            state.nextDueAt = clock.now
            state.mistakeReturn = false
        }
        card.updatedAt = clock.now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The learning state could not be saved. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }
}
