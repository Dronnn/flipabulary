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
        .all
    }
}

// MARK: - Sort enum

enum WidgetSortOption: String, AppEnum, Sendable {
    case dueFirst
    case alphabetical
    case recentlyAdded

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sort"
    static let caseDisplayRepresentations: [WidgetSortOption: DisplayRepresentation] = [
        .dueFirst: DisplayRepresentation(title: "Due first"),
        .alphabetical: DisplayRepresentation(title: "Alphabetical"),
        .recentlyAdded: DisplayRepresentation(title: "Recently added")
    ]

    var model: WidgetSort {
        switch self {
        case .dueFirst: .dueFirst
        case .alphabetical: .alphabetical
        case .recentlyAdded: .recentlyAdded
        }
    }
}

// MARK: - Intents

struct SummaryConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Summary"
    static let description = IntentDescription("Choose a stack for the vocabulary summary.")

    @Parameter(title: "Use app defaults", default: true)
    var useAppDefaults: Bool

    @Parameter(title: "Stack")
    var stack: WidgetStackEntity?
}

struct ListConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Word list"
    static let description = IntentDescription("Choose what the word list shows.")

    @Parameter(title: "Use app defaults", default: true)
    var useAppDefaults: Bool

    @Parameter(title: "Stack")
    var stack: WidgetStackEntity?

    @Parameter(title: "Sort", default: .dueFirst)
    var sort: WidgetSortOption

    @Parameter(title: "Show translations", default: false)
    var showTranslations: Bool
}
