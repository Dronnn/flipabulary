import AppIntents
import Foundation
import WidgetKit

// MARK: - Stack entity

struct WidgetStackEntity: AppEntity, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stack"
    static let defaultQuery = WidgetStackQuery()

    var id: String
    var name: String
    var isAllStacks: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let all = WidgetStackEntity(id: "all", name: "All stacks", isAllStacks: true)

    var stackID: UUID? {
        isAllStacks ? nil : UUID(uuidString: id)
    }
}

struct WidgetStackQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetStackEntity] {
        let stacks = WidgetSnapshotStore.shared.load()?.stacks ?? []
        var result: [WidgetStackEntity] = []
        for identifier in identifiers {
            if identifier == WidgetStackEntity.all.id {
                result.append(.all)
            } else if let stack = stacks.first(where: { $0.id.uuidString == identifier }) {
                result.append(WidgetStackEntity(id: identifier, name: stack.name, isAllStacks: false))
            }
        }
        return result
    }

    func suggestedEntities() async throws -> [WidgetStackEntity] {
        let stacks = WidgetSnapshotStore.shared.load()?.stacks ?? []
        return [.all] + stacks.map {
            WidgetStackEntity(id: $0.id.uuidString, name: $0.name, isAllStacks: false)
        }
    }

    func defaultResult() async -> WidgetStackEntity? {
        guard let snapshot = WidgetSnapshotStore.shared.load() else { return .all }
        if let stackID = snapshot.defaultStackID, let stack = snapshot.stack(id: stackID) {
            return WidgetStackEntity(id: stackID.uuidString, name: stack.name, isAllStacks: false)
        }
        return .all
    }
}

// MARK: - Combined source entity

struct WidgetSourceEntity: AppEntity, Sendable {
    enum Kind: String, Codable, Sendable {
        case all
        case stack
        case wordSet
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Source"
    static let defaultQuery = WidgetSourceQuery()

    var id: String
    var name: String
    var kind: Kind

    static let all = WidgetSourceEntity(id: "all", name: "All stacks", kind: .all)

    static func stack(_ stack: WidgetStackSnapshot) -> WidgetSourceEntity {
        WidgetSourceEntity(id: stack.id.uuidString, name: stack.name, kind: .stack)
    }

    static func wordSet(_ set: WidgetWordSetSnapshot) -> WidgetSourceEntity {
        WidgetSourceEntity(id: set.id.uuidString, name: set.name, kind: .wordSet)
    }

    var stackID: UUID? {
        kind == .stack ? UUID(uuidString: id) : nil
    }

    var wordSetID: UUID? {
        kind == .wordSet ? UUID(uuidString: id) : nil
    }

    var displayRepresentation: DisplayRepresentation {
        switch kind {
        case .all:
            DisplayRepresentation(title: "\(name)")
        case .stack:
            DisplayRepresentation(title: "\(name)", subtitle: "Stack")
        case .wordSet:
            DisplayRepresentation(title: "\(name)", subtitle: "Word set")
        }
    }
}

struct WidgetSourceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetSourceEntity] {
        let snapshot = WidgetSnapshotStore.shared.load()
        return identifiers.compactMap { identifier in
            if identifier == WidgetSourceEntity.all.id { return .all }
            if let stack = snapshot?.stacks.first(where: { $0.id.uuidString == identifier }) {
                return .stack(stack)
            }
            if let set = snapshot?.wordSets.first(where: { $0.id.uuidString == identifier }) {
                return .wordSet(set)
            }
            return nil
        }
    }

    func suggestedEntities() async throws -> [WidgetSourceEntity] {
        guard let snapshot = WidgetSnapshotStore.shared.load() else { return [.all] }
        return [.all]
            + snapshot.stacks.map(WidgetSourceEntity.stack)
            + snapshot.wordSets.map(WidgetSourceEntity.wordSet)
    }

    func defaultResult() async -> WidgetSourceEntity? {
        guard let snapshot = WidgetSnapshotStore.shared.load() else { return .all }
        if let setID = snapshot.defaultWordSetID, let set = snapshot.wordSet(id: setID) {
            return .wordSet(set)
        }
        if let stackID = snapshot.defaultStackID, let stack = snapshot.stack(id: stackID) {
            return .stack(stack)
        }
        return .all
    }
}

// MARK: - Sort enum

enum WidgetSortOption: String, AppEnum, Sendable {
    case dueFirst
    case alphabetical
    case recentlyAdded
    case manual

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sort"
    static let caseDisplayRepresentations: [WidgetSortOption: DisplayRepresentation] = [
        .dueFirst: DisplayRepresentation(title: "Due first"),
        .alphabetical: DisplayRepresentation(title: "Alphabetical"),
        .recentlyAdded: DisplayRepresentation(title: "Recently added"),
        .manual: DisplayRepresentation(title: "Manual")
    ]

    var model: WidgetSort {
        switch self {
        case .dueFirst: .dueFirst
        case .alphabetical: .alphabetical
        case .recentlyAdded: .recentlyAdded
        case .manual: .manual
        }
    }
}

// MARK: - Intents

struct SummaryConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Summary"
    static let description = IntentDescription("Choose a stack for the vocabulary summary.")

    @Parameter(title: "Stack")
    var stack: WidgetStackEntity?
}

struct ListConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Word list"
    static let description = IntentDescription("Choose a stack or a custom word set, then pick the order.")

    @Parameter(title: "Source")
    var source: WidgetSourceEntity?

    @Parameter(title: "Sort", default: .manual)
    var sort: WidgetSortOption

    @Parameter(title: "Show translations", default: false)
    var showTranslations: Bool
}
