import SwiftUI
import WidgetKit

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlipWidgetEntry {
        WidgetData.makeEntry(
            date: Date(),
            snapshot: .galleryPlaceholder,
            isPlaceholder: true
        )
    }

    func snapshot(for configuration: ListConfigurationIntent, in context: Context) async -> FlipWidgetEntry {
        let snapshot = WidgetData.snapshot(preview: context.isPreview)
        return WidgetData.makeEntry(
            date: Date(),
            snapshot: snapshot,
            source: configuration.source,
            sortOverride: configuration.sort.model,
            translationsOverride: configuration.showTranslations,
            isPlaceholder: context.isPreview
        )
    }

    func timeline(for configuration: ListConfigurationIntent, in context: Context) async -> Timeline<FlipWidgetEntry> {
        let now = Date()
        let snapshot = WidgetData.snapshot(preview: context.isPreview)
        return WidgetData.timeline(snapshot: snapshot, now: now) { date in
            WidgetData.makeEntry(
                date: date,
                snapshot: snapshot,
                source: configuration.source,
                sortOverride: configuration.sort.model,
                translationsOverride: configuration.showTranslations,
                isPlaceholder: context.isPreview
            )
        }
    }
}

struct FlipabularyListWidget: Widget {
    static let kind = "FlipabularyListWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: ListConfigurationIntent.self,
            provider: ListProvider()
        ) { entry in
            ListWidgetView(entry: entry)
                .environment(\.locale, entry.locale)
                .containerBackground(for: .widget) {
                    AppColor.page
                }
        }
        .configurationDisplayName("Word list")
        .description("See words from a stack, sorted for the next review.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct ListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlipWidgetEntry
    var familyOverride: WidgetFamily?

    private var resolvedFamily: WidgetFamily { familyOverride ?? family }

    var body: some View {
        Group {
            switch resolvedFamily {
            case .systemSmall:
                small
            case .systemMedium:
                medium
            case .systemLarge:
                large
            case .systemExtraLarge:
                extraLarge
            default:
                medium
            }
        }
        .widgetURL(entry.wordsURL)
        .accessibilityElement(children: .contain)
    }

    private var cards: [WidgetCardSnapshot] {
        Array(entry.cards.prefix(capacity))
    }

    private var sizeClass: WidgetSizeClass {
        switch resolvedFamily {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    private var capacity: Int { sizeClass.entryCapacity }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                WidgetWordmark()
                Spacer()
                Text("\(entry.summary.due) due")
                    .font(AppFont.font(9, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            if cards.isEmpty {
                WidgetEmptyState(
                    title: entry.summary.saved == 0 ? "No words yet" : "All caught up",
                    message: entry.summary.saved == 0 ? "Add words in Flipabulary." : "Open Flipabulary to add more."
                )
            } else {
                VStack(spacing: 5) {
                    ForEach(cards) { card in
                        WidgetListRow(card: card, showTranslation: entry.showTranslations, compact: true)
                    }
                }
                Spacer(minLength: 0)
                Text(entry.isStale ? "Open app to refresh" : "\(entry.summary.due) due · \(entry.scopeName)")
                    .font(AppFont.font(8, .medium))
                    .foregroundStyle(AppColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .accessibilityLabel("\(entry.scopeName), \(cards.count) words shown, \(entry.summary.due) due")
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if cards.isEmpty {
                WidgetEmptyState(
                    title: entry.summary.saved == 0 ? "No words yet" : "All caught up",
                    message: entry.summary.saved == 0 ? "Add words in Flipabulary." : "Nothing due right now."
                )
            } else {
                let split = (cards.count + 1) / 2
                HStack(alignment: .top, spacing: 10) {
                    column(cards: Array(cards.prefix(split)), compact: true)
                    Rectangle().fill(AppColor.divider).frame(width: 1)
                    column(cards: Array(cards.dropFirst(split)), compact: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if cards.isEmpty {
                WidgetEmptyState(
                    title: entry.summary.saved == 0 ? "No words yet" : "All caught up",
                    message: entry.summary.saved == 0 ? "Add words in Flipabulary." : "Nothing due right now."
                )
            } else {
                let split = (cards.count + 1) / 2
                HStack(alignment: .top, spacing: 14) {
                    column(cards: Array(cards.prefix(split)), compact: false)
                    Rectangle().fill(AppColor.divider).frame(width: 1)
                    column(cards: Array(cards.dropFirst(split)), compact: false)
                }
                Spacer(minLength: 0)
                staleFooter
            }
        }
        .padding(16)
    }

    // MARK: Extra large

    private var extraLarge: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if cards.isEmpty {
                WidgetEmptyState(
                    title: entry.summary.saved == 0 ? "No words yet" : "All caught up",
                    message: entry.summary.saved == 0 ? "Add words in Flipabulary." : "Nothing due right now."
                )
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        VStack(spacing: 0) {
                            if let url = cardURL(card) {
                                Link(destination: url) {
                                    WidgetListRow(card: card, showTranslation: entry.showTranslations)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                }
                            } else {
                                WidgetListRow(card: card, showTranslation: entry.showTranslations)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            }
                            if index < cards.count - 4 {
                                Rectangle().fill(AppColor.divider).frame(height: 1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                staleFooter
            }
        }
        .padding(18)
    }

    // MARK: Shared pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Words")
                    .font(AppFont.font(18, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("\(entry.scopeName) · \(entry.summary.due) due")
                    .font(AppFont.font(10, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            if entry.missingConfiguredWordSet {
                Text("Configured word set unavailable. Showing \(entry.scopeName).")
                    .font(AppFont.font(8.5, .medium))
                    .foregroundStyle(AppColor.textSecondary)
            } else if entry.missingConfiguredStack {
                Text("Configured stack unavailable. Showing \(entry.scopeName).")
                    .font(AppFont.font(8.5, .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func column(cards: [WidgetCardSnapshot], compact: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                if let url = cardURL(card) {
                    Link(destination: url) {
                        WidgetListRow(card: card, showTranslation: entry.showTranslations, compact: compact)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, compact ? 4 : 7)
                    }
                } else {
                    WidgetListRow(card: card, showTranslation: entry.showTranslations, compact: compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, compact ? 4 : 7)
                }
                if index < cards.count - 1 {
                    Rectangle()
                        .fill(AppColor.divider)
                        .frame(height: 1)
                        .padding(.leading, compact ? 31 : 37)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var staleFooter: some View {
        if entry.isStale {
            Text("Open Flipabulary to refresh this snapshot.")
                .font(AppFont.font(8, .medium))
                .foregroundStyle(AppColor.textMuted)
        }
    }

    private func cardURL(_ card: WidgetCardSnapshot) -> URL? {
        resolvedFamily == .systemSmall ? nil : AppLinks.card(id: card.id)
    }
}
