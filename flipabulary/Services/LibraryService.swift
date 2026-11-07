import Foundation
import SwiftData

struct CardDraft: Equatable, Sendable {
    var word: String = ""
    var sourceExample: String = ""
    var translation: String = ""
    var translatedExample: String = ""
    var phonetic: String = ""
    var partOfSpeech: String = ""
    var stackID: UUID?
    var tagNames: [String] = []

    init() {}

    init(card: VocabularyCard) {
        word = card.word
        sourceExample = card.sourceExample ?? ""
        translation = card.translation
        translatedExample = card.translatedExample ?? ""
        phonetic = card.phonetic ?? ""
        partOfSpeech = card.partOfSpeech ?? ""
        stackID = card.stack?.id
        tagNames = card.tags.map(\.name).sorted()
    }

    var trimmedWord: String { word.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedTranslation: String { translation.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSourceExample: String { sourceExample.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedTranslatedExample: String { translatedExample.trimmingCharacters(in: .whitespacesAndNewlines) }

    var normalizedTagNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in tagNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = SearchNormalizer.normalize(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

extension CardDraft {
    func validateBasic(stackExists: Bool) -> CardValidation {
        var result = CardValidation.valid
        if trimmedWord.isEmpty {
            result.wordError = "Enter a word."
        } else if trimmedWord.count > 200 {
            result.wordError = "Use \(trimmedWord.count - 200) fewer characters."
        }
        if trimmedTranslation.isEmpty {
            result.translationError = "Enter a translation."
        } else if trimmedTranslation.count > 200 {
            result.translationError = "Use \(trimmedTranslation.count - 200) fewer characters."
        }
        if trimmedSourceExample.count > 2_000 {
            result.sourceExampleError = "Examples are limited to 2,000 characters."
        }
        if trimmedTranslatedExample.count > 2_000 {
            result.translatedExampleError = "Examples are limited to 2,000 characters."
        }
        if !stackExists {
            result.stackError = "Choose a stack."
        }
        if normalizedTagNames.contains(where: { $0.count > 60 }) {
            result.tagError = "Tag names are limited to 60 characters."
        }
        return result
    }
}

struct LibraryListSnapshot: Sendable {
    var index: CardListIndex
    var dueCount: Int
}

struct CardValidation: Equatable, Sendable {
    var wordError: String?
    var translationError: String?
    var sourceExampleError: String?
    var translatedExampleError: String?
    var stackError: String?
    var tagError: String?

    static let valid = CardValidation(
        wordError: nil,
        translationError: nil,
        sourceExampleError: nil,
        translatedExampleError: nil,
        stackError: nil,
        tagError: nil
    )

    var isValid: Bool {
        wordError == nil && translationError == nil && sourceExampleError == nil
            && translatedExampleError == nil && stackError == nil && tagError == nil
    }
}

enum LibraryWriteError: Error, LocalizedError {
    case invalid(CardValidation)
    case duplicate(UUID)
    case missingStack
    case invalidName(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "Check the highlighted fields."
        case .duplicate:
            return "This word and translation already exist in the selected stack."
        case .missingStack:
            return "Choose a stack before saving."
        case .invalidName(let message):
            return message
        case .storage(let message):
            return message
        }
    }
}

enum StackDeletionMode: Sendable {
    case moveCardsToDefault
    case deleteCards
}

@MainActor
final class LibraryService {
    let modelContext: ModelContext
    let preferences: PreferencesStore
    let maintenance: MaintenanceService
    let clock: DateProviding

    init(
        modelContext: ModelContext,
        preferences: PreferencesStore,
        maintenance: MaintenanceService,
        clock: DateProviding = SystemClock()
    ) {
        self.modelContext = modelContext
        self.preferences = preferences
        self.maintenance = maintenance
        self.clock = clock
    }

    // MARK: Reads

    func stacks() -> [VocabularyStack] {
        maintenance.stacks()
    }

    func cards() -> [VocabularyCard] {
        maintenance.cards()
    }

    func tags() -> [VocabularyTag] {
        (try? modelContext.fetch(FetchDescriptor<VocabularyTag>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func displayModels() -> [CardDisplayModel] {
        displayModels(stacks: stacks())
    }

    func displayModels(stacks: [VocabularyStack]) -> [CardDisplayModel] {
        LibraryProjection.displayModels(
            cards: maintenance.cardsForList(),
            stacks: stacks,
            globalRules: preferences.preferences.rules,
            recentGradesByCard: recentGradesByCard()
        )
    }

    func buildListSnapshot(
        scopeID: UUID?,
        rules: LearningRules,
        now: Date,
        calendar: Calendar
    ) async -> LibraryListSnapshot? {
        let container = modelContext.container
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let stacks = (try? context.fetch(
                FetchDescriptor<VocabularyStack>(sortBy: [SortDescriptor(\.createdAt)])
            )) ?? []
            var cardDescriptor = FetchDescriptor<VocabularyCard>()
            cardDescriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState, \.tags]
            let cards = (try? context.fetch(cardDescriptor)) ?? []
            let records = (try? context.fetch(FetchDescriptor<DailyAdmissionRecord>())) ?? []
            let events = (try? context.fetch(
                FetchDescriptor<ReviewEvent>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            )) ?? []

            var recentByCard: [UUID: [CardHistoryItem]] = [:]
            recentByCard.reserveCapacity(events.count)
            for event in events {
                var items = recentByCard[event.cardID, default: []]
                guard items.count < 5 else { continue }
                items.append(CardHistoryItem(grade: event.grade, timestamp: event.timestamp))
                recentByCard[event.cardID] = items
            }

            let displays = LibraryProjection.displayModels(
                cards: cards,
                stacks: stacks,
                globalRules: rules,
                recentGradesByCard: recentByCard
            )
            let index = CardListIndex(cards: displays)
            let dueCount = LibraryProjection.dueCount(
                scopeID: scopeID,
                stacks: stacks,
                cards: cards,
                records: records,
                globalRules: rules,
                now: now,
                calendar: calendar
            )
            return LibraryListSnapshot(index: index, dueCount: dueCount)
        }.value
    }

    func computeDueCount(
        scopeID: UUID?,
        rules: LearningRules,
        now: Date,
        calendar: Calendar
    ) async -> Int {
        let container = modelContext.container
        return await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let stacks = (try? context.fetch(FetchDescriptor<VocabularyStack>())) ?? []
            var cardDescriptor = FetchDescriptor<VocabularyCard>()
            cardDescriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState]
            let cards = (try? context.fetch(cardDescriptor)) ?? []
            let records = (try? context.fetch(FetchDescriptor<DailyAdmissionRecord>())) ?? []
            return LibraryProjection.dueCount(
                scopeID: scopeID,
                stacks: stacks,
                cards: cards,
                records: records,
                globalRules: rules,
                now: now,
                calendar: calendar
            )
        }.value
    }

    func recentGradesByCard(limit: Int = 5) -> [UUID: [CardHistoryItem]] {
        let descriptor = FetchDescriptor<ReviewEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let events = try? modelContext.fetch(descriptor), !events.isEmpty else { return [:] }
        var result: [UUID: [CardHistoryItem]] = [:]
        result.reserveCapacity(events.count)
        for event in events {
            var items = result[event.cardID, default: []]
            guard items.count < limit else { continue }
            items.append(CardHistoryItem(grade: event.grade, timestamp: event.timestamp))
            result[event.cardID] = items
        }
        return result
    }

    func defaultStack() -> VocabularyStack? {
        let descriptor = FetchDescriptor<VocabularyStack>(predicate: #Predicate { $0.isDefault })
        if let stack = try? modelContext.fetch(descriptor).first {
            return stack
        }
        return stacks().first
    }

    func stack(id: UUID?) -> VocabularyStack? {
        guard let id else { return nil }
        let targetID = id
        let descriptor = FetchDescriptor<VocabularyStack>(predicate: #Predicate { $0.id == targetID })
        return try? modelContext.fetch(descriptor).first
    }

    func selectedStack() -> VocabularyStack? {
        stack(id: preferences.preferences.selectedStackID) ?? defaultStack()
    }

    func card(id: UUID) -> VocabularyCard? {
        let targetID = id
        var descriptor = FetchDescriptor<VocabularyCard>(predicate: #Predicate { $0.id == targetID })
        descriptor.relationshipKeyPathsForPrefetching = [\.stack, \.learningState, \.tags]
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: Validation

    func validate(_ draft: CardDraft, excluding: UUID? = nil) -> CardValidation {
        let exists = draft.stackID != nil && stack(id: draft.stackID) != nil
        return draft.validateBasic(stackExists: exists)
    }

    func duplicate(of draft: CardDraft, excluding cardID: UUID? = nil) -> VocabularyCard? {
        guard let stackID = draft.stackID, let stack = stack(id: stackID) else { return nil }
        let word = SearchNormalizer.normalize(draft.trimmedWord)
        let translation = SearchNormalizer.normalize(draft.trimmedTranslation)
        return stack.cards.first { card in
            card.id != cardID
                && SearchNormalizer.normalize(card.word) == word
                && SearchNormalizer.normalize(card.translation) == translation
        }
    }

    // MARK: Card writes

    func saveCard(
        draft: CardDraft,
        existing: VocabularyCard?,
        addAnyway: Bool = false
    ) -> Result<VocabularyCard, LibraryWriteError> {
        let validation = validate(draft, excluding: existing?.id)
        guard validation.isValid else { return .failure(.invalid(validation)) }
        guard let stackID = draft.stackID, let stack = stack(id: stackID) else {
            return .failure(.missingStack)
        }
        if !addAnyway, let duplicate = duplicate(of: draft, excluding: existing?.id) {
            return .failure(.duplicate(duplicate.id))
        }

        let card: VocabularyCard
        if let existing {
            card = existing
        } else {
            card = VocabularyCard(
                word: draft.trimmedWord,
                translation: draft.trimmedTranslation,
                stack: stack,
                createdAt: clock.now
            )
            modelContext.insert(card)
        }

        card.word = draft.trimmedWord
        card.translation = draft.trimmedTranslation
        card.sourceExample = draft.trimmedSourceExample.isEmpty ? nil : draft.trimmedSourceExample
        card.translatedExample = draft.trimmedTranslatedExample.isEmpty ? nil : draft.trimmedTranslatedExample
        card.phonetic = draft.phonetic.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        card.partOfSpeech = draft.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        card.stack = stack
        card.updatedAt = clock.now
        card.tags = resolveTags(draft.normalizedTagNames)

        if existing == nil, card.learningState == nil {
            let state = CardLearningState(card: card)
            modelContext.insert(state)
            card.learningState = state
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The card could not be saved. Your draft is still here. \(error.localizedDescription)"))
        }

        maintenance.publishSnapshot()
        return .success(card)
    }

    func deleteCard(_ card: VocabularyCard) -> Result<Void, LibraryWriteError> {
        modelContext.delete(card)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The card could not be deleted. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }

    func findOrCreateTag(named name: String) -> VocabularyTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return nil }
        let normalized = SearchNormalizer.normalize(trimmed)
        if let existing = tags().first(where: { SearchNormalizer.normalize($0.name) == normalized }) {
            return existing
        }
        let tag = VocabularyTag(name: trimmed, createdAt: clock.now)
        modelContext.insert(tag)
        return tag
    }

    private func resolveTags(_ names: [String]) -> [VocabularyTag] {
        guard !names.isEmpty else { return [] }
        var cache: [String: VocabularyTag] = [:]
        for tag in tags() {
            cache[SearchNormalizer.normalize(tag.name)] = tag
        }
        return names.compactMap { rawName in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { return nil }
            let key = SearchNormalizer.normalize(name)
            if let existing = cache[key] { return existing }
            let tag = VocabularyTag(name: name, createdAt: clock.now)
            modelContext.insert(tag)
            cache[key] = tag
            return tag
        }
    }

    // MARK: Stack writes

    func createStack(named rawName: String) -> Result<VocabularyStack, LibraryWriteError> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.invalidName("Enter a stack name.")) }
        guard name.count <= 60 else { return .failure(.invalidName("Stack names are limited to 60 characters.")) }
        let normalized = SearchNormalizer.normalize(name)
        if stacks().contains(where: { SearchNormalizer.normalize($0.name) == normalized }) {
            return .failure(.invalidName("A stack with this name already exists."))
        }
        let stack = VocabularyStack(name: name, createdAt: clock.now)
        modelContext.insert(stack)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The stack could not be created. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(stack)
    }

    func renameStack(_ stack: VocabularyStack, to rawName: String) -> Result<Void, LibraryWriteError> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.invalidName("Enter a stack name.")) }
        guard name.count <= 60 else { return .failure(.invalidName("Stack names are limited to 60 characters.")) }
        let normalized = SearchNormalizer.normalize(name)
        if stacks().contains(where: { $0.id != stack.id && SearchNormalizer.normalize($0.name) == normalized }) {
            return .failure(.invalidName("A stack with this name already exists."))
        }
        stack.name = name
        stack.updatedAt = clock.now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The stack could not be renamed. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }

    func deleteStack(_ stack: VocabularyStack, mode: StackDeletionMode) -> Result<Void, LibraryWriteError> {
        if stack.isDefault {
            return .failure(.invalidName("The My words stack can't be deleted."))
        }
        switch mode {
        case .moveCardsToDefault:
            guard let destination = defaultStack(), destination.id != stack.id else {
                return .failure(.invalidName("A destination stack is unavailable."))
            }
            for card in stack.cards {
                card.stack = destination
                card.updatedAt = clock.now
            }
        case .deleteCards:
            for card in stack.cards {
                modelContext.delete(card)
            }
        }
        if preferences.preferences.selectedStackID == stack.id {
            preferences.preferences.selectedStackID = defaultStack()?.id
        }
        if preferences.preferences.widgetDefaults.stackID == stack.id {
            preferences.preferences.widgetDefaults.stackID = defaultStack()?.id
        }
        if preferences.preferences.reminders.stackID == stack.id {
            preferences.preferences.reminders.stackID = nil
        }
        modelContext.delete(stack)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("The stack could not be deleted. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }

    func saveStackSettings(_ stack: VocabularyStack) -> Result<Void, LibraryWriteError> {
        stack.cardsPerSession = min(max(stack.cardsPerSession, 1), 100)
        stack.newCardsPerDay = min(max(stack.newCardsPerDay, 0), 100)
        stack.steps = LearningRules.validatedSteps(stack.steps)
        stack.updatedAt = clock.now
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return .failure(.storage("Settings could not be saved. \(error.localizedDescription)"))
        }
        maintenance.publishSnapshot()
        return .success(())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
