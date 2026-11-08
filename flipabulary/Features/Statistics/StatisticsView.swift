import SwiftUI
import SwiftData
import Charts
import Combine

struct StatisticsView: View {
    @Environment(AppEnvironment.self) private var app
    let stackID: UUID?

    @State private var rangeDays = 30
    @State private var statistics: LibraryStatistics?
    @State private var isLoading = true
    @State private var refreshTask: Task<Void, Never>?

    private var scopeName: String {
        guard let stackID else { return "Statistics" }
        return app.library.stack(id: stackID)?.name ?? "Stack statistics"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let statistics {
                    rangePicker
                    summary(statistics)
                    timeChart(statistics)
                    answersChart(statistics)
                    if stackID == nil {
                        stackBreakdown(statistics)
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    EmptyStateView(
                        title: "No statistics yet",
                        message: "Complete a review to see your progress."
                    )
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .pageBackground()
        .navigationTitle(LocalizedStringKey(scopeName))
        .navigationBarTitleDisplayMode(.large)
        .task(id: rangeDays) {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            scheduleReload()
        }
    }

    private func scheduleReload() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func load() async {
        let live = stackID == nil ? app.currentAppUsageInterval() : nil
        let result = await app.library.libraryStatistics(
            stackID: stackID,
            rangeDays: rangeDays,
            now: Date(),
            calendar: app.maintenance.calendar,
            liveAppUsage: live
        )
        guard !Task.isCancelled else { return }
        statistics = result
        isLoading = false
    }

    private var rangePicker: some View {
        Picker("Range", selection: $rangeDays) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("statistics.range")
    }

    private func summary(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Summary")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                if stackID == nil {
                    metricTile(
                        title: "App time",
                        value: DurationFormatting.short(stats.totalAppSeconds),
                        systemImage: "iphone"
                    )
                }
                metricTile(
                    title: "Review time",
                    value: DurationFormatting.short(stats.totalReviewSeconds),
                    systemImage: "clock"
                )
                if stackID != nil, let stack = stats.stacks.first {
                    metricTile(
                        title: "Session time",
                        value: DurationFormatting.short(stack.activeSessionSeconds),
                        systemImage: "timer"
                    )
                }
                metricTile(
                    title: "Reviews",
                    value: "\(stats.totalReviews)",
                    systemImage: "checkmark.message"
                )
                metricTile(
                    title: "Accuracy",
                    value: stats.accuracy.formatted(.percent.precision(.fractionLength(0))),
                    systemImage: "target"
                )
                metricTile(
                    title: "Good",
                    value: "\(stats.totalGood)",
                    systemImage: "arrow.right.circle.fill"
                )
                metricTile(
                    title: "Again",
                    value: "\(stats.totalAgain)",
                    systemImage: "arrow.left.circle.fill"
                )
            }
            GroupedSurface {
                HStack(spacing: 12) {
                    Text(String(format: app.localized("%lld saved"), stats.saved))
                    Text(verbatim: "·")
                    Text(String(format: app.localized("%lld learned"), stats.learned))
                    Text(verbatim: "·")
                    Text(String(format: app.localized("%lld mastered"), stats.mastered))
                }
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textSecondary)
                .padding(16)
            }
        }
    }

    private func metricTile(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.accentStrong)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.font(11, .medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(AppFont.font(19, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .raisedSurface(radius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }

    private func timeChart(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Time per day")
            GroupedSurface {
                if stats.days.allSatisfy({ $0.reviewSeconds == 0 && $0.appSeconds == 0 }) {
                    Text("No statistics yet")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    let appLabel = app.localized("App time")
                    let reviewLabel = app.localized("Review time")
                    Chart(stats.days) { day in
                        if stackID == nil {
                            BarMark(
                                x: .value("Day", day.date),
                                y: .value("Minutes", day.appSeconds / 60)
                            )
                            .foregroundStyle(by: .value("Kind", appLabel))
                            LineMark(
                                x: .value("Day", day.date),
                                y: .value("Minutes", day.reviewSeconds / 60)
                            )
                            .foregroundStyle(by: .value("Kind", reviewLabel))
                        } else {
                            BarMark(
                                x: .value("Day", day.date),
                                y: .value("Minutes", day.reviewSeconds / 60)
                            )
                            .foregroundStyle(AppColor.accentStrong)
                        }
                    }
                    .chartForegroundStyleScale([
                        appLabel: AppColor.accentSoft,
                        reviewLabel: AppColor.accentStrong
                    ])
                    .chartYAxisLabel("Minutes")
                    .frame(height: 190)
                    .padding(16)
                }
            }
        }
    }

    private func answersChart(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Answers per day")
            GroupedSurface {
                if stats.days.allSatisfy({ $0.reviews == 0 }) {
                    Text("No statistics yet")
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    let goodLabel = app.localized("Good")
                    let againLabel = app.localized("Again")
                    Chart(stats.days) { day in
                        BarMark(
                            x: .value("Day", day.date),
                            y: .value("Count", day.good)
                        )
                        .foregroundStyle(by: .value("Answer", goodLabel))
                        BarMark(
                            x: .value("Day", day.date),
                            y: .value("Count", day.again)
                        )
                        .foregroundStyle(by: .value("Answer", againLabel))
                    }
                    .chartForegroundStyleScale([
                        goodLabel: AppColor.success,
                        againLabel: AppColor.danger
                    ])
                    .frame(height: 190)
                    .padding(16)
                }
            }
        }
    }

    private func stackBreakdown(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "By stack")
            GroupedSurface {
                ForEach(Array(stats.stacks.enumerated()), id: \.element.id) { index, stack in
                    NavigationLink(value: AppRoute.statistics(stack.id)) {
                        HStack(spacing: 12) {
                            InitialTile(word: stack.name, id: stack.id, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stack.name)
                                    .font(AppFont.fieldValue())
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(String(format: app.localized("%lld reviews"), stack.reviews))
                                    Text(verbatim: "·")
                                    Text(DurationFormatting.short(stack.reviewSeconds))
                                }
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Text(stack.accuracy.formatted(.percent.precision(.fractionLength(0))))
                                .font(AppFont.font(13, .semibold))
                                .foregroundStyle(AppColor.textSecondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < stats.stacks.count - 1 {
                        SettingsDivider(inset: 66)
                    }
                }
            }
        }
    }
}
