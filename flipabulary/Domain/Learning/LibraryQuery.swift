import Foundation

enum SearchNormalizer {
    static func normalize(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .precomposedStringWithCanonicalMapping
    }
}

struct LibraryAggregate: Equatable, Sendable {
    var saved = 0
    var new = 0
    var learning = 0
    var learned = 0
    var difficult = 0

    init() {}

    init(cards: [CardDisplayModel]) {
        for card in cards {
            add(card)
        }
    }

    mutating func add(_ card: CardDisplayModel, difficult isDifficult: Bool? = nil) {
        saved += 1
        switch card.lifecycle {
        case .new: new += 1
        case .learning: learning += 1
        case .learned: learned += 1
        }
        if isDifficult ?? card.isDifficult {
            difficult += 1
        }
    }

    func summary(due: Int) -> LibrarySummary {
        LibrarySummary(
            saved: saved,
            due: due,
            new: new,
            learning: learning,
            learned: learned,
            difficult: difficult
        )
    }

    var categories: [CategorySummary] {
        [
            CategorySummary(filter: .new, count: new),
            CategorySummary(filter: .learning, count: learning),
            CategorySummary(filter: .learned, count: learned),
            CategorySummary(filter: .difficult, count: difficult)
        ]
    }
}

/// Pre-sorted card data with normalized search keys and per-stack counts.
/// Build it once when library data changes; filtering then never re-normalizes
/// or re-sorts the library on every render or keystroke.
struct CardListIndex: Sendable {
    struct Entry: Sendable {
        var card: CardDisplayModel
        var searchKey: Data

        func matches(_ query: Data) -> Bool {
            searchKey.range(of: query) != nil
        }
    }

    let entries: [Entry]
    let all: LibraryAggregate
    let byStack: [UUID: LibraryAggregate]

    init(cards: [CardDisplayModel] = []) {
        let sorted = cards.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var all = LibraryAggregate()
        var byStack: [UUID: LibraryAggregate] = [:]
        entries = sorted.map { card in
            let isDifficult = card.isDifficult
            all.add(card, difficult: isDifficult)
            byStack[card.stackID, default: LibraryAggregate()].add(card, difficult: isDifficult)
            let searchKey = ([card.word, card.translation] + card.tagNames)
                .map(SearchNormalizer.normalize)
                .joined(separator: "\u{1f}")
            return Entry(
                card: card,
                searchKey: Data(searchKey.utf8)
            )
        }
        self.all = all
        self.byStack = byStack
    }

    func aggregate(stackID: UUID?) -> LibraryAggregate {
        guard let stackID else { return all }
        return byStack[stackID] ?? LibraryAggregate()
    }

    func removing(cardID: UUID) -> CardListIndex {
        guard entries.contains(where: { $0.card.id == cardID }) else { return self }
        let remaining = entries.filter { $0.card.id != cardID }
        var all = LibraryAggregate()
        var byStack: [UUID: LibraryAggregate] = [:]
        for entry in remaining {
            let isDifficult = entry.card.isDifficult
            all.add(entry.card, difficult: isDifficult)
            byStack[entry.card.stackID, default: LibraryAggregate()].add(entry.card, difficult: isDifficult)
        }
        return CardListIndex(entries: remaining, all: all, byStack: byStack)
    }

    private init(entries: [Entry], all: LibraryAggregate, byStack: [UUID: LibraryAggregate]) {
        self.entries = entries
        self.all = all
        self.byStack = byStack
    }

    func filter(
        stackID: UUID?,
        filter: CardFilter,
        search: String,
        limit: Int? = nil
    ) -> [CardDisplayModel] {
        let normalizedSearch = SearchNormalizer.normalize(search)
        let query = normalizedSearch.isEmpty ? nil : Data(normalizedSearch.utf8)
        var result: [CardDisplayModel] = []
        result.reserveCapacity(min(limit ?? entries.count, entries.count))
        for entry in entries {
            if let stackID, entry.card.stackID != stackID { continue }
            guard filter.matches(lifecycle: entry.card.lifecycle, isDifficult: entry.card.isDifficult) else { continue }
            if let query, !entry.matches(query) { continue }
            result.append(entry.card)
            if let limit, result.count >= limit { break }
        }
        return result
    }
}

enum LibraryQuery {
    static func scoped(_ cards: [CardDisplayModel], stackID: UUID?) -> [CardDisplayModel] {
        guard let stackID else { return cards }
        return cards.filter { $0.stackID == stackID }
    }

    static func filter(
        _ cards: [CardDisplayModel],
        stackID: UUID?,
        filter: CardFilter,
        search: String
    ) -> [CardDisplayModel] {
        let scope = scoped(cards, stackID: stackID)
        let query = SearchNormalizer.normalize(search)
        let filtered = scope.filter { card in
            guard filter.matches(lifecycle: card.lifecycle, isDifficult: card.isDifficult) else { return false }
            guard !query.isEmpty else { return true }
            if SearchNormalizer.normalize(card.word).contains(query) { return true }
            if SearchNormalizer.normalize(card.translation).contains(query) { return true }
            return card.tagNames.contains { SearchNormalizer.normalize($0).contains(query) }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func summary(
        allCards: [CardDisplayModel],
        stackID: UUID?,
        dueCount: Int
    ) -> LibrarySummary {
        LibraryAggregate(cards: scoped(allCards, stackID: stackID)).summary(due: dueCount)
    }

    static func categoryCounts(allCards: [CardDisplayModel], stackID: UUID?) -> [CategorySummary] {
        LibraryAggregate(cards: scoped(allCards, stackID: stackID)).categories
    }

    static func relativeRatio(count: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    static func recentGrades(from events: [ReviewEvent], limit: Int = 5) -> [CardHistoryItem] {
        events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { CardHistoryItem(grade: $0.grade, timestamp: $0.timestamp) }
    }
}
