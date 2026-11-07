import Foundation

enum SearchNormalizer {
    static func normalize(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .precomposedStringWithCanonicalMapping
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
        let scope = scoped(allCards, stackID: stackID)
        return LibrarySummary(
            saved: scope.count,
            due: dueCount,
            new: scope.filter { $0.lifecycle == .new }.count,
            learning: scope.filter { $0.lifecycle == .learning }.count,
            learned: scope.filter { $0.lifecycle == .learned }.count,
            difficult: scope.filter(\.isDifficult).count
        )
    }

    static func categoryCounts(allCards: [CardDisplayModel], stackID: UUID?) -> [CategorySummary] {
        let scope = scoped(allCards, stackID: stackID)
        return [
            CategorySummary(filter: .new, count: scope.filter { $0.lifecycle == .new }.count),
            CategorySummary(filter: .learning, count: scope.filter { $0.lifecycle == .learning }.count),
            CategorySummary(filter: .learned, count: scope.filter { $0.lifecycle == .learned }.count),
            CategorySummary(filter: .difficult, count: scope.filter(\.isDifficult).count)
        ]
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
