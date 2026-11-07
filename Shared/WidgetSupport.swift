import Foundation
import SwiftUI
import WidgetKit

struct FlipWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let stackID: UUID?
    let sort: WidgetSort
    let showTranslations: Bool
    let missingConfiguredStack: Bool
    let isPlaceholder: Bool

    var scopeName: String {
        snapshot.stack(id: stackID)?.name ?? "All stacks"
    }

    var summary: WidgetSummary {
        snapshot.summary(stackID: stackID)
    }

    var cards: [WidgetCardSnapshot] {
        snapshot.projectedCards(stackID: stackID, sort: sort)
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

    static func resolveStackID(
        snapshot: WidgetSnapshot,
        useAppDefaults: Bool,
        requested: WidgetStackEntity?
    ) -> UUID? {
        if useAppDefaults {
            return snapshot.resolvedStackID(snapshot.defaultStackID)
        }
        if let requested, let id = requested.stackID {
            return snapshot.resolvedStackID(id)
        }
        return nil
    }

    static func makeEntry(
        date: Date,
        snapshot: WidgetSnapshot,
        useAppDefaults: Bool,
        requestedStack: WidgetStackEntity?,
        sortOverride: WidgetSort? = nil,
        translationsOverride: Bool? = nil,
        isPlaceholder: Bool = false
    ) -> FlipWidgetEntry {
        let requestedID = requestedStack?.stackID
        let stackID: UUID?
        if useAppDefaults && requestedStack == nil {
            stackID = snapshot.resolvedStackID(snapshot.defaultStackID)
        } else if let requestedID {
            stackID = snapshot.resolvedStackID(requestedID)
        } else {
            stackID = nil
        }
        let missing = requestedID != nil && snapshot.stack(id: requestedID!) == nil
        return FlipWidgetEntry(
            date: date,
            snapshot: snapshot,
            stackID: stackID,
            sort: useAppDefaults ? snapshot.defaultSort : (sortOverride ?? .dueFirst),
            showTranslations: useAppDefaults ? snapshot.defaultShowTranslations : (translationsOverride ?? false),
            missingConfiguredStack: missing,
            isPlaceholder: isPlaceholder
        )
    }

    static func timeline(
        snapshot: WidgetSnapshot,
        now: Date,
        makeEntry: (Date) -> FlipWidgetEntry
    ) -> Timeline<FlipWidgetEntry> {
        var dates: [Date] = [now]
        let upcoming = snapshot.stacks
            .compactMap(\.nextDueAt)
            .filter { $0 > now }
            .sorted()
            .prefix(2)
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
