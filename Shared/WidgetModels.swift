import Foundation

// MARK: - Shared widget read model

enum WidgetSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case dueFirst
    case alphabetical
    case recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueFirst: "Due first"
        case .alphabetical: "Alphabetical"
        case .recentlyAdded: "Recently added"
        }
    }
}

struct WidgetCardSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var word: String
    var translation: String
    var lifecycle: String
    var repeatCount: Int
    var threshold: Int
    var dueAt: Date?
    var createdAt: Date
}

struct WidgetStackSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var savedCount: Int
    var dueCount: Int
    var learnedCount: Int
    var learningCount: Int
    var newCount: Int
    var cards: [WidgetCardSnapshot]
    var nextDueAt: Date?
}

struct WidgetSnapshot: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var stacks: [WidgetStackSnapshot]
    var defaultStackID: UUID?
    var defaultSort: WidgetSort
    var defaultShowTranslations: Bool
    var languageCode: String? = nil

    static let empty = WidgetSnapshot(
        schemaVersion: currentSchemaVersion,
        generatedAt: .distantPast,
        stacks: [],
        defaultStackID: nil,
        defaultSort: .dueFirst,
        defaultShowTranslations: false
    )

    static var galleryPlaceholder: WidgetSnapshot {
        let stackID = UUID()
        let now = Date()
        let cards = [
            WidgetCardSnapshot(id: UUID(), word: "ephemeral", translation: "мимолетный", lifecycle: "learning", repeatCount: 3, threshold: 5, dueAt: now, createdAt: now),
            WidgetCardSnapshot(id: UUID(), word: "ubiquitous", translation: "вездесущий", lifecycle: "learning", repeatCount: 1, threshold: 5, dueAt: now, createdAt: now),
            WidgetCardSnapshot(id: UUID(), word: "mitigate", translation: "смягчать", lifecycle: "new", repeatCount: 0, threshold: 5, dueAt: nil, createdAt: now),
            WidgetCardSnapshot(id: UUID(), word: "resilient", translation: "устойчивый", lifecycle: "learning", repeatCount: 2, threshold: 5, dueAt: now, createdAt: now),
            WidgetCardSnapshot(id: UUID(), word: "ambiguous", translation: "двусмысленный", lifecycle: "learning", repeatCount: 4, threshold: 5, dueAt: now, createdAt: now)
        ]
        return WidgetSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: now,
            stacks: [
                WidgetStackSnapshot(
                    id: stackID,
                    name: "My words",
                    savedCount: 5,
                    dueCount: 4,
                    learnedCount: 0,
                    learningCount: 4,
                    newCount: 1,
                    cards: cards,
                    nextDueAt: now
                )
            ],
            defaultStackID: stackID,
            defaultSort: .dueFirst,
            defaultShowTranslations: false
        )
    }

    var isEmpty: Bool { stacks.allSatisfy(\.cards.isEmpty) }

    func stack(id: UUID?) -> WidgetStackSnapshot? {
        guard let id else { return nil }
        return stacks.first(where: { $0.id == id })
    }

    func resolvedStackID(_ requested: UUID?) -> UUID? {
        if let requested, stack(id: requested) != nil { return requested }
        if let defaultStackID, stack(id: defaultStackID) != nil { return defaultStackID }
        return stacks.first(where: { !$0.cards.isEmpty })?.id ?? stacks.first?.id
    }

    func missingRequestedStack(_ requested: UUID?) -> Bool {
        guard let requested else { return false }
        return stack(id: requested) == nil
    }

    func projectedCards(stackID: UUID?, sort: WidgetSort) -> [WidgetCardSnapshot] {
        let cards: [WidgetCardSnapshot]
        if let stack = stack(id: stackID) {
            cards = stack.cards
        } else {
            cards = stacks.flatMap(\.cards)
        }
        switch sort {
        case .dueFirst:
            return cards.sorted { lhs, rhs in
                let l = lhs.dueAt ?? .distantFuture
                let r = rhs.dueAt ?? .distantFuture
                if l != r { return l < r }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .alphabetical:
            return cards.sorted { lhs, rhs in
                let comparison = lhs.word.localizedStandardCompare(rhs.word)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .recentlyAdded:
            return cards.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    func summary(stackID: UUID?) -> WidgetSummary {
        if let stack = stack(id: stackID) {
            return WidgetSummary(
                saved: stack.savedCount,
                due: stack.dueCount,
                learned: stack.learnedCount,
                learning: stack.learningCount,
                new: stack.newCount,
                cards: stack.cards,
                nextDueAt: stack.nextDueAt
            )
        }
        return WidgetSummary(
            saved: stacks.reduce(0) { $0 + $1.savedCount },
            due: stacks.reduce(0) { $0 + $1.dueCount },
            learned: stacks.reduce(0) { $0 + $1.learnedCount },
            learning: stacks.reduce(0) { $0 + $1.learningCount },
            new: stacks.reduce(0) { $0 + $1.newCount },
            cards: stacks.flatMap(\.cards),
            nextDueAt: stacks.compactMap(\.nextDueAt).min()
        )
    }
}

enum WidgetSizeClass: String, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var entryCapacity: Int {
        switch self {
        case .small: 3
        case .medium: 6
        case .large: 10
        case .extraLarge: 16
        }
    }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

extension WidgetSnapshot {
    func listCards(stackID: UUID?, sort: WidgetSort, size: WidgetSizeClass) -> [WidgetCardSnapshot] {
        Array(projectedCards(stackID: stackID, sort: sort).prefix(size.entryCapacity))
    }
}

struct WidgetSummary: Hashable, Sendable {
    var saved: Int
    var due: Int
    var learned: Int
    var learning: Int
    var new: Int
    var cards: [WidgetCardSnapshot]
    var nextDueAt: Date?

    var learnedProgress: Double {
        guard saved > 0 else { return 0 }
        return Double(learned) / Double(saved)
    }

    var nextCard: WidgetCardSnapshot? {
        cards
            .filter { $0.lifecycle != "learned" }
            .sorted {
                let l = $0.dueAt ?? .distantFuture
                let r = $1.dueAt ?? .distantFuture
                if l != r { return l < r }
                return $0.createdAt < $1.createdAt
            }
            .first
    }

    var upcomingCards: [WidgetCardSnapshot] {
        cards
            .filter { $0.lifecycle != "learned" }
            .sorted {
                let l = $0.dueAt ?? .distantFuture
                let r = $1.dueAt ?? .distantFuture
                if l != r { return l < r }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}

// MARK: - Deep links

enum AppLinks {
    static let scheme = "flipabulary"

    static func words(stackID: UUID?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "words"
        if let stackID {
            components.queryItems = [URLQueryItem(name: "stack", value: stackID.uuidString)]
        }
        return components.url ?? URL(string: "\(scheme)://words")!
    }

    static func review(stackID: UUID?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "review"
        if let stackID {
            components.queryItems = [URLQueryItem(name: "stack", value: stackID.uuidString)]
        }
        return components.url ?? URL(string: "\(scheme)://review")!
    }

    static func card(id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "card"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url ?? URL(string: "\(scheme)://words")!
    }
}

enum AppDestination: Hashable, Sendable {
    case words(stackID: UUID?)
    case review(stackID: UUID?)
    case card(id: UUID)
    case settings
    case widgets
    case reminders

    static func parse(_ url: URL) -> AppDestination? {
        guard url.scheme == AppLinks.scheme, let host = url.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func uuid(_ name: String) -> UUID? {
            items.first(where: { $0.name == name })?.value.flatMap(UUID.init(uuidString:))
        }
        switch host {
        case "words":
            return .words(stackID: uuid("stack"))
        case "review":
            return .review(stackID: uuid("stack"))
        case "card":
            guard let id = uuid("id") else { return .words(stackID: nil) }
            return .card(id: id)
        case "settings":
            return .settings
        case "widgets":
            return .widgets
        case "reminders":
            return .reminders
        default:
            return nil
        }
    }
}
