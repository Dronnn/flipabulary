import Foundation
import SwiftData

struct StackMergeResult {
    let stack: VocabularyStack
    let mergedCardCount: Int
    let duplicateCount: Int
    let removedStackCount: Int
}

extension LibraryService {
    func mergeStacks(
        _ stackIDs: [UUID],
        named rawName: String,
        deleteOriginals: Bool
    ) -> Result<StackMergeResult, LibraryWriteError> {
        let ids = uniqueIDs(stackIDs)
        guard ids.count >= 2 else {
            return .failure(.invalidName("Select at least two stacks to merge."))
        }

        let selected = ids.compactMap { stack(id: $0) }
        guard selected.count == ids.count else {
            return .failure(.storage("The selected stacks are no longer available."))
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(.invalidName("Enter a stack name."))
        }
        guard name.count <= 60 else {
            return .failure(.invalidName("Stack names are limited to 60 characters."))
        }

        let selectedIDs = Set(ids)
        let survivingStacks: [VocabularyStack]
        if deleteOriginals {
            survivingStacks = stacks().filter { !selectedIDs.contains($0.id) || $0.isDefault }
        } else {
            survivingStacks = stacks()
        }
        let normalizedName = SearchNormalizer.normalize(name)
        if survivingStacks.contains(where: { SearchNormalizer.normalize($0.name) == normalizedName }) {
            return .failure(.invalidName("A stack with this name already exists."))
        }

        let topSortOrder = (stacks().map(\.sortOrder).min() ?? 0) - 1
        let merged = VocabularyStack(name: name, createdAt: clock.now, sortOrder: topSortOrder)
        modelContext.insert(merged)

        let protectedStackIDs = Set(selected.filter(\.isDefault).map(\.id))
        let groups = groupedCards(in: selected)
        var removedCardIDMap: [UUID: UUID] = [:]
        var duplicateCount = 0
        let now = clock.now

        for group in groups {
            guard let winner = bestCard(in: group) else { continue }
            duplicateCount += max(0, group.count - 1)

            let winnerIsProtected = isProtected(winner, protectedStackIDs: protectedStackIDs)
            let mergedCard: VocabularyCard
            if deleteOriginals && !winnerIsProtected {
                mergedCard = winner
                mergedCard.stack = merged
                mergedCard.updatedAt = now
            } else {
                mergedCard = copyCard(winner, into: merged, now: now)
            }

            mergeFields(from: group, into: mergedCard, winner: winner, now: now)

            if deleteOriginals {
                for card in group where card.id != winner.id && !isProtected(card, protectedStackIDs: protectedStackIDs) {
                    removedCardIDMap[card.id] = mergedCard.id
                    moveReviewEvents(from: card, to: mergedCard)
                    modelContext.delete(card)
                }
            }
        }

        let removedStacks: [VocabularyStack]
        if deleteOriginals {
            removedStacks = selected.filter { !$0.isDefault }
            for stack in removedStacks {
                modelContext.delete(stack)
            }
        } else {
            removedStacks = []
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The merged stack could not be saved. \(error.localizedDescription)"))
        }

        var updatedPreferences = preferences.preferences
        updatedPreferences.selectedStackID = merged.id
        if deleteOriginals {
            let removedStackIDs = Set(removedStacks.map(\.id))
            if let widgetStackID = updatedPreferences.widgetDefaults.stackID,
               removedStackIDs.contains(widgetStackID) {
                updatedPreferences.widgetDefaults.stackID = merged.id
            }
            if let reminderStackID = updatedPreferences.reminders.stackID,
               removedStackIDs.contains(reminderStackID) {
                updatedPreferences.reminders.stackID = merged.id
            }
            updatedPreferences.widgetWordSets = updatedPreferences.widgetWordSets.map { set in
                var seen = Set<UUID>()
                var cardIDs: [UUID] = []
                for cardID in set.cardIDs {
                    let mapped = removedCardIDMap[cardID] ?? cardID
                    if seen.insert(mapped).inserted {
                        cardIDs.append(mapped)
                    }
                }
                var updated = set
                updated.cardIDs = cardIDs
                return updated
            }
        }
        preferences.preferences = updatedPreferences
        maintenance.publishSnapshot()

        return .success(
            StackMergeResult(
                stack: merged,
                mergedCardCount: groups.count,
                duplicateCount: duplicateCount,
                removedStackCount: removedStacks.count
            )
        )
    }
}

private extension LibraryService {
    func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    func groupedCards(in stacks: [VocabularyStack]) -> [[VocabularyCard]] {
        var groups: [String: [VocabularyCard]] = [:]
        var order: [String] = []
        for stack in stacks {
            let cards = stack.cards.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
            for card in cards {
                let key = mergeKey(word: card.word, translation: card.translation)
                if groups[key] == nil {
                    order.append(key)
                }
                groups[key, default: []].append(card)
            }
        }
        return order.compactMap { groups[$0] }
    }

    func mergeKey(word: String, translation: String) -> String {
        let pair = [
            SearchNormalizer.normalize(word),
            SearchNormalizer.normalize(translation)
        ].sorted()
        return pair.joined(separator: "\u{1f}")
    }

    func bestCard(in group: [VocabularyCard]) -> VocabularyCard? {
        group.sorted { lhs, rhs in
            let lhsRank = progressRank(lhs)
            let rhsRank = progressRank(rhs)
            if lhsRank.lifecycle != rhsRank.lifecycle {
                return lhsRank.lifecycle > rhsRank.lifecycle
            }
            if lhsRank.stage != rhsRank.stage {
                return lhsRank.stage > rhsRank.stage
            }
            if lhsRank.totalGrades != rhsRank.totalGrades {
                return lhsRank.totalGrades > rhsRank.totalGrades
            }
            if lhsRank.repeatCount != rhsRank.repeatCount {
                return lhsRank.repeatCount > rhsRank.repeatCount
            }
            if lhsRank.lastGradedAt != rhsRank.lastGradedAt {
                return lhsRank.lastGradedAt > rhsRank.lastGradedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }

    func progressRank(_ card: VocabularyCard) -> (lifecycle: Int, stage: Int, totalGrades: Int, repeatCount: Int, lastGradedAt: Date) {
        let state = card.learningState
        let lifecycle: Int = switch state?.lifecycle {
        case .learned: 3
        case .learning: 2
        case .new, nil: 1
        }
        return (
            lifecycle: lifecycle,
            stage: state?.lifecycle == .learned ? (state?.reviewStageIndex ?? 0) : (state?.stepIndex ?? 0),
            totalGrades: state?.totalGrades ?? 0,
            repeatCount: state?.repeatCount ?? 0,
            lastGradedAt: state?.lastGradedAt ?? .distantPast
        )
    }

    func isProtected(_ card: VocabularyCard, protectedStackIDs: Set<UUID>) -> Bool {
        guard let stackID = card.stack?.id else { return false }
        return protectedStackIDs.contains(stackID)
    }

    func copyCard(_ source: VocabularyCard, into stack: VocabularyStack, now: Date) -> VocabularyCard {
        let copy = VocabularyCard(
            word: source.word,
            translation: source.translation,
            sourceExample: source.sourceExample,
            translatedExample: source.translatedExample,
            phonetic: source.phonetic,
            partOfSpeech: source.partOfSpeech,
            stack: stack,
            tags: source.tags,
            createdAt: now
        )
        copy.difficultOverride = source.difficultOverride
        copy.updatedAt = now
        modelContext.insert(copy)

        if let sourceState = source.learningState {
            let state = copy.learningState ?? CardLearningState(card: copy)
            if copy.learningState == nil {
                modelContext.insert(state)
                copy.learningState = state
            }
            state.apply(sourceState.snapshot, rulesVersion: sourceState.rulesVersion)
            state.totalGrades = sourceState.totalGrades
        }
        return copy
    }

    func mergeFields(
        from group: [VocabularyCard],
        into target: VocabularyCard,
        winner: VocabularyCard,
        now: Date
    ) {
        let winnerWord = SearchNormalizer.normalize(winner.word)
        let winnerTranslation = SearchNormalizer.normalize(winner.translation)

        for card in group where card.id != winner.id {
            let word = SearchNormalizer.normalize(card.word)
            let translation = SearchNormalizer.normalize(card.translation)

            if word == winnerTranslation && translation == winnerWord {
                target.sourceExample = nonEmpty(target.sourceExample) ?? nonEmpty(card.translatedExample)
                target.translatedExample = nonEmpty(target.translatedExample) ?? nonEmpty(card.sourceExample)
            } else if word == winnerWord && translation == winnerTranslation {
                target.sourceExample = nonEmpty(target.sourceExample) ?? nonEmpty(card.sourceExample)
                target.translatedExample = nonEmpty(target.translatedExample) ?? nonEmpty(card.translatedExample)
                target.phonetic = nonEmpty(target.phonetic) ?? nonEmpty(card.phonetic)
                target.partOfSpeech = nonEmpty(target.partOfSpeech) ?? nonEmpty(card.partOfSpeech)
            }
        }

        var tagNames: [String] = []
        var seenTags = Set<String>()
        for card in group {
            for tag in card.tags {
                let key = SearchNormalizer.normalize(tag.name)
                if seenTags.insert(key).inserted {
                    tagNames.append(tag.name)
                }
            }
        }
        target.tags = resolveTags(tagNames)

        if group.contains(where: { $0.difficultOverride == true }) {
            target.difficultOverride = true
        }
        target.updatedAt = now
    }

    func moveReviewEvents(from source: VocabularyCard, to target: VocabularyCard) {
        for event in source.reviewEvents {
            event.card = target
            event.cardID = target.id
        }
    }

    func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
