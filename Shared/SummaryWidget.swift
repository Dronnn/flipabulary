import SwiftUI
import WidgetKit

struct SummaryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlipWidgetEntry {
        WidgetData.makeEntry(
            date: Date(),
            snapshot: .galleryPlaceholder,
            requestedStack: nil,
            isPlaceholder: true
        )
    }

    func snapshot(for configuration: SummaryConfigurationIntent, in context: Context) async -> FlipWidgetEntry {
        let snapshot = WidgetData.snapshot(preview: context.isPreview)
        return WidgetData.makeEntry(
            date: Date(),
            snapshot: snapshot,
            requestedStack: configuration.stack,
            isPlaceholder: context.isPreview
        )
    }

    func timeline(for configuration: SummaryConfigurationIntent, in context: Context) async -> Timeline<FlipWidgetEntry> {
        let now = Date()
        let snapshot = WidgetData.snapshot(preview: context.isPreview)
        return WidgetData.timeline(snapshot: snapshot, now: now) { date in
            WidgetData.makeEntry(
                date: date,
                snapshot: snapshot,
                requestedStack: configuration.stack,
                isPlaceholder: context.isPreview
            )
        }
    }
}

struct FlipabularySummaryWidget: Widget {
    static let kind = "FlipabularySummaryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SummaryConfigurationIntent.self,
            provider: SummaryProvider()
        ) { entry in
            SummaryWidgetView(entry: entry)
                .environment(\.locale, entry.locale)
                .containerBackground(for: .widget) {
                    AppColor.page
                }
        }
        .configurationDisplayName("Vocabulary summary")
        .description("See due words, learned progress, and what is coming next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
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

    private var summary: WidgetSummary { entry.summary }

    private var empty: Bool { summary.saved == 0 }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                WidgetWordmark()
                Spacer()
                if entry.isStale {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColor.textMuted)
                        .accessibilityLabel("Open Flipabulary to refresh")
                }
            }
            Spacer(minLength: 2)
            ZStack {
                ProgressRing(
                    progress: summary.learnedProgress,
                    lineWidth: 8,
                    size: 110,
                    label: "\(summary.learned) of \(summary.saved) words learned"
                )
                if empty {
                    Text("No words yet")
                        .font(AppFont.font(13, .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                } else {
                    VStack(spacing: 0) {
                        Text("\(summary.due)")
                            .font(AppFont.font(32, .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("due")
                            .font(AppFont.font(10, .medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityLabel(empty ? "No words yet" : "\(summary.due) due, \(summary.saved) saved, \(summary.learned) learned")
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ZStack {
                    ProgressRing(
                        progress: summary.learnedProgress,
                        lineWidth: 9,
                        size: 104,
                        label: "\(summary.learned) of \(summary.saved) words learned"
                    )
                    VStack(spacing: 0) {
                        Text("\(summary.due)")
                            .font(AppFont.font(28, .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("due")
                            .font(AppFont.font(9, .medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                Text(entry.scopeName)
                    .font(AppFont.font(9, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 130)

            Rectangle()
                .fill(AppColor.divider)
                .frame(width: 1)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                if entry.missingConfiguredStack {
                    Text("Stack unavailable · showing \(entry.scopeName)")
                        .font(AppFont.font(9, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                if empty {
                    WidgetEmptyState(title: "No words yet", message: "Add words in Flipabulary.")
                } else if let next = summary.nextCard {
                    Text("NEXT UP")
                        .font(AppFont.font(9, .semibold))
                        .tracking(1.6)
                        .foregroundStyle(AppColor.accentStrong)
                    Link(destination: AppLinks.card(id: next.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.word)
                                .font(AppFont.font(21, .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(next.translation)
                                .font(AppFont.font(12, .regular))
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    HStack(spacing: 7) {
                        RepeatBars(count: next.repeatCount, threshold: next.threshold, barWidth: 3, height: 12)
                        Text("\(next.repeatCount) / \(next.threshold)")
                            .font(AppFont.font(9, .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("All caught up")
                        .font(AppFont.font(18, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Open Flipabulary to add more words.")
                        .font(AppFont.font(10, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .accessibilityLabel("\(entry.scopeName), \(summary.due) due, \(summary.saved) saved")
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Words")
                        .font(AppFont.font(22, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(entry.localizedDate)
                        .font(AppFont.font(10, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Text(entry.scopeName)
                    .font(AppFont.font(10, .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    ProgressRing(
                        progress: summary.learnedProgress,
                        lineWidth: 11,
                        size: 140,
                        label: "\(summary.learned) of \(summary.saved) words learned"
                    )
                    VStack(spacing: 0) {
                        Text("\(summary.due)")
                            .font(AppFont.font(38, .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("due")
                            .font(AppFont.font(10, .medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    summaryStat("Words", summary.saved)
                    summaryStat("Learned", summary.learned)
                    summaryStat("Learning", summary.learning)
                }
            }

            Divider().overlay(AppColor.divider)

            if empty {
                WidgetEmptyState(title: "No words yet", message: "Add words in Flipabulary.")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(summary.upcomingCards.prefix(3))) { card in
                        Link(destination: AppLinks.card(id: card.id)) {
                            HStack(spacing: 8) {
                                InitialTile(word: card.word, id: card.id, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(card.word)
                                        .font(AppFont.font(13, .semibold))
                                        .foregroundStyle(AppColor.textPrimary)
                                        .lineLimit(1)
                                    Text(card.translation)
                                        .font(AppFont.font(10, .regular))
                                        .foregroundStyle(AppColor.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                RepeatBars(count: card.repeatCount, threshold: card.threshold, barWidth: 2.5, height: 10)
                                Text("\(card.repeatCount)/\(card.threshold)")
                                    .font(AppFont.font(8.5, .medium))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
    }

    private func summaryStat(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(AppFont.font(11, .medium))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text("\(value)")
                .font(AppFont.font(18, .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: Extra large

    private var extraLarge: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Words")
                    .font(AppFont.font(30, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(summary.saved) saved · \(summary.due) due · \(entry.scopeName)")
                    .font(AppFont.font(13, .regular))
                    .foregroundStyle(AppColor.textSecondary)
                ZStack {
                    ProgressRing(
                        progress: summary.learnedProgress,
                        lineWidth: 14,
                        size: 180,
                        label: "\(summary.learned) of \(summary.saved) words learned"
                    )
                    VStack(spacing: 0) {
                        Text("\(summary.due)")
                            .font(AppFont.font(46, .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .widgetAccentable()
                        Text("due")
                            .font(AppFont.font(12, .medium))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(.vertical, 2)
                HStack(spacing: 20) {
                    summaryStat("Words", summary.saved)
                    summaryStat("Learned", summary.learned)
                    summaryStat("Learning", summary.learning)
                }
                if entry.missingConfiguredStack {
                    Text("Configured stack unavailable. Showing \(entry.scopeName).")
                        .font(AppFont.font(10, .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 330, alignment: .leading)

            Rectangle()
                .fill(AppColor.divider)
                .frame(width: 1)
                .padding(.vertical, 8)

            if empty {
                WidgetEmptyState(title: "No words yet", message: "Open Flipabulary to add words.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(summary.upcomingCards.prefix(4))) { card in
                        Link(destination: AppLinks.card(id: card.id)) {
                            VStack(alignment: .leading, spacing: 5) {
                                WidgetCardTile(card: card, showTranslation: true)
                                Spacer(minLength: 0)
                                HStack {
                                    Text(card.lifecycle.capitalized)
                                        .font(AppFont.font(8, .medium))
                                        .foregroundStyle(AppColor.textSecondary)
                                    Spacer()
                                    Text(card.dueAt?.formatted(date: .abbreviated, time: .omitted) ?? "New")
                                        .font(AppFont.font(8, .medium))
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColor.divider, lineWidth: 1))
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(22)
    }
}
