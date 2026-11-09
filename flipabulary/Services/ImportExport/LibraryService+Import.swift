import Foundation
import SwiftData

extension LibraryService {
    func importPlan(_ plan: ImportPlan, destinationStackID: UUID?) -> Result<ImportSummary, LibraryWriteError> {
        var stackCache: [String: VocabularyStack] = [:]
        for stack in stacks() {
            stackCache[SearchNormalizer.normalize(stack.name)] = stack
        }
        var usedStackNames = Set(stackCache.keys)
        var tagCache: [String: VocabularyTag] = [:]
        for tag in tags() {
            tagCache[SearchNormalizer.normalize(tag.name)] = tag
        }

        var imported = 0
        var skipped = plan.skippedRows
        var usedStacks = Set<String>()
        var newStacks: [VocabularyStack] = []
        let importDate = clock.now
        let topSortOrder = (stacks().map(\.sortOrder).min() ?? 0) - 1

        func normalized(_ value: String) -> String {
            SearchNormalizer.normalize(value)
        }

        func sanitizedStackName(_ raw: String) -> String {
            let cleaned = raw
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = cleaned.isEmpty ? "Imported words" : cleaned
            return String(base.prefix(60))
        }

        func stack(named raw: String) -> VocabularyStack {
            let name = sanitizedStackName(raw)
            let key = normalized(name)
            if let existing = stackCache[key] { return existing }

            var candidate = name
            var suffix = 2
            while usedStackNames.contains(normalized(candidate)) {
                candidate = String("\(name) \(suffix)".prefix(60))
                suffix += 1
            }
            let stack = VocabularyStack(
                name: candidate,
                createdAt: importDate,
                sortOrder: topSortOrder - newStacks.count
            )
            modelContext.insert(stack)
            newStacks.append(stack)
            stackCache[normalized(candidate)] = stack
            usedStackNames.insert(normalized(candidate))
            return stack
        }

        func tag(named raw: String) -> VocabularyTag? {
            let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !name.isEmpty else { return nil }
            let key = normalized(name)
            if let existing = tagCache[key] { return existing }
            let tag = VocabularyTag(name: name, createdAt: importDate)
            modelContext.insert(tag)
            tagCache[key] = tag
            return tag
        }

        var duplicateKeys: [UUID: Set<String>] = [:]

        func importCards(_ cards: [ImportedCard], into stack: VocabularyStack) {
            let stackID = stack.id
            var keys = duplicateKeys[stackID] ?? Set(
                stack.cards.map { normalized($0.word) + "\u{1f}" + normalized($0.translation) }
            )

            for card in cards {
                let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
                let translation = card.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, !translation.isEmpty,
                      word.count <= 200, translation.count <= 200 else {
                    skipped += 1
                    continue
                }
                let key = normalized(word) + "\u{1f}" + normalized(translation)
                guard keys.insert(key).inserted else {
                    skipped += 1
                    continue
                }

                let created = importDate.addingTimeInterval(Double(imported + 1) / 1_000)
                let model = VocabularyCard(
                    word: word,
                    translation: translation,
                    sourceExample: card.example,
                    translatedExample: card.translatedExample,
                    phonetic: card.phonetic,
                    partOfSpeech: card.partOfSpeech,
                    stack: stack,
                    tags: card.tags.compactMap(tag(named:)),
                    createdAt: created
                )
                model.updatedAt = created
                modelContext.insert(model)
                imported += 1
                usedStacks.insert(stack.name)
            }
            duplicateKeys[stackID] = keys
        }

        if plan.usesDeckNames {
            for deck in plan.decks where !deck.cards.isEmpty {
                importCards(deck.cards, into: stack(named: deck.name))
            }
        } else {
            let destination: VocabularyStack
            if let destinationStackID, let existing = self.stack(id: destinationStackID) {
                destination = existing
            } else {
                destination = stack(named: plan.suggestedStackName)
            }
            for deck in plan.decks {
                importCards(deck.cards, into: destination)
            }
        }

        for stack in newStacks where !usedStacks.contains(stack.name) {
            modelContext.delete(stack)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The imported words could not be saved. \(error.localizedDescription)"))
        }

        maintenance.refresh()
        return .success(
            ImportSummary(
                imported: imported,
                skipped: skipped,
                stacks: usedStacks.sorted()
            )
        )
    }
}
