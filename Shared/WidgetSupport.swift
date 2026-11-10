import Foundation
import SwiftUI
import WidgetKit

struct FlipWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let stackID: UUID?
    let wordSetID: UUID?
    let sort: WidgetSort
    let showTranslations: Bool
    let missingConfiguredStack: Bool
    let missingConfiguredWordSet: Bool
    let isPlaceholder: Bool

    var scopeName: String {
        if let wordSet = snapshot.wordSet(id: wordSetID) { return wordSet.name }
        return snapshot.stack(id: stackID)?.name ?? "All stacks"
    }

    var summary: WidgetSummary {
        snapshot.summary(stackID: stackID, wordSetID: wordSetID)
    }

    var cards: [WidgetCardSnapshot] {
        snapshot.projectedCards(stackID: stackID, wordSetID: wordSetID, sort: sort)
    }

    var wordsURL: URL {
        AppLinks.words(stackID: stackID)
    }

    var locale: Locale {
        if let languageCode = snapshot.languageCode {
            return Locale(identifier: languageCode)
        }
        return Locale.current
    }

    var localizedDate: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var isStale: Bool {
        guard !isPlaceholder, snapshot.generatedAt != .distantPast else { return false }
        return date.timeIntervalSince(snapshot.generatedAt) > 7 * 86_400
    }
}

enum WidgetData {
    static func snapshot(preview: Bool) -> WidgetSnapshot {
        if preview { return .galleryPlaceholder }
        return WidgetSnapshotStore.shared.load() ?? .empty
    }

    static func makeEntry(
        date: Date,
        snapshot: WidgetSnapshot,
        source: WidgetSourceEntity? = nil,
        requestedStack: WidgetStackEntity? = nil,
        sortOverride: WidgetSort? = nil,
        translationsOverride: Bool? = nil,
        isPlaceholder: Bool = false
    ) -> FlipWidgetEntry {
        let stackID: UUID?
        let wordSetID: UUID?
        var missingStack = false
        var missingSet = false

        if let source {
            switch source.kind {
            case .all:
                stackID = nil
                wordSetID = nil
            case .stack:
                if let id = source.stackID, snapshot.stack(id: id) != nil {
                    stackID = id
                    wordSetID = nil
                } else {
                    missingStack = true
                    stackID = snapshot.defaultStackID
                    wordSetID = nil
                }
            case .wordSet:
                if let id = source.wordSetID, snapshot.wordSet(id: id) != nil {
                    wordSetID = id
                    stackID = nil
                } else {
                    missingSet = true
                    if let id = snapshot.defaultWordSetID, snapshot.wordSet(id: id) != nil {
                        wordSetID = id
                    } else {
                        wordSetID = nil
                    }
                    stackID = nil
                }
            }
        } else if let requestedStack {
            stackID = requestedStack.isAllStacks ? nil : snapshot.resolvedStackID(requestedStack.stackID)
            wordSetID = nil
        } else if let defaultSetID = snapshot.defaultWordSetID, snapshot.wordSet(id: defaultSetID) != nil {
            wordSetID = defaultSetID
            stackID = nil
        } else if let defaultStackID = snapshot.defaultStackID, snapshot.stack(id: defaultStackID) != nil {
            wordSetID = nil
            stackID = defaultStackID
        } else {
            wordSetID = nil
            stackID = nil
        }

        return FlipWidgetEntry(
            date: date,
            snapshot: snapshot.projected(at: date),
            stackID: stackID,
            wordSetID: wordSetID,
            sort: sortOverride ?? .dueFirst,
            showTranslations: translationsOverride ?? false,
            missingConfiguredStack: missingStack,
            missingConfiguredWordSet: missingSet,
            isPlaceholder: isPlaceholder
        )
    }

    static func timeline(
        snapshot: WidgetSnapshot,
        now: Date,
        makeEntry: (Date) -> FlipWidgetEntry
    ) -> Timeline<FlipWidgetEntry> {
        var dates: [Date] = [now]
        let upcoming = Set(snapshot.stacks.flatMap(\.cards).compactMap(\.dueAt))
            .filter { $0 > now }
            .sorted()
            .prefix(48)
        dates.append(contentsOf: upcoming)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        dates.append(midnight)
        let unique = Array(Set(dates.filter { $0 >= now })).sorted()
        let entries = unique.map(makeEntry)
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct WidgetHeader: View {
    let title: String
    let detail: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.font(15, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.font(9, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(AppFont.font(10, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

struct WidgetEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(AppFont.font(12, .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text(LocalizedStringKey(message))
                .font(AppFont.font(9, .regular))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}
