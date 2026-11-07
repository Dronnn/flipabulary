import SwiftUI
import SwiftData
import UIKit

struct WordsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \VocabularyStack.createdAt) private var stacks: [VocabularyStack]
    @Query private var records: [DailyAdmissionRecord]

    @State private var searchText = ""
    @State private var now = Date()
    @State private var pendingEndSession: ReviewSession?

    private var preferences: AppPreferences { app.preferences.preferences }

    private var selectedStack: VocabularyStack? {
        guard let id = preferences.selectedStackID else { return nil }
        return stacks.first(where: { $0.id == id })
    }

    private var displays: [CardDisplayModel] {
        LibraryProjection.displayModels(stacks: stacks, globalRules: preferences.rules)
    }

    private var displayedCards: [CardDisplayModel] {
        LibraryQuery.filter(
            displays,
            stackID: preferences.selectedStackID,
            filter: preferences.filter,
            search: searchText
        )
    }

    private var dueCount: Int {
        LibraryProjection.dueCount(
            scopeID: preferences.selectedStackID,
            stacks: stacks,
            records: records,
            globalRules: preferences.rules,
            now: now,
            calendar: app.maintenance.calendar
        )
    }

    private var summary: LibrarySummary {
        LibraryQuery.summary(
            allCards: displays,
            stackID: preferences.selectedStackID,
            dueCount: dueCount
        )
    }

    private var categories: [CategorySummary] {
        LibraryQuery.categoryCounts(allCards: displays, stackID: preferences.selectedStackID)
    }

    private var scopeName: String {
        selectedStack?.name ?? "All stacks"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mode = AppMetrics.LayoutMode.resolve(width: width)
            let effectiveMode: AppMetrics.LayoutMode = dynamicTypeSize.isAccessibilitySize ? .compact : mode
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let session = app.review.latestActiveSession() {
                        activeSessionBanner(session)
                    }
                    if effectiveMode == .compact {
                        compactContent(width: width)
                    } else {
                        expandedContent(width: width, mode: effectiveMode)
                    }
                }
                .frame(maxWidth: effectiveMode == .compact ? .infinity : min(width, AppMetrics.maxWorkingWidth), alignment: .center)
                .padding(.horizontal, effectiveMode.inset)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "End unfinished session?",
            isPresented: Binding(
                get: { pendingEndSession != nil },
                set: { if !$0 { pendingEndSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("End session", role: .destructive) {
                if let session = pendingEndSession {
                    _ = app.review.endSession(session)
                    app.router.showToast("Session ended. Completed ratings were kept.")
                }
                pendingEndSession = nil
            }
            Button("Continue learning", role: .cancel) { pendingEndSession = nil }
        } message: {
            Text("Reviewed answers are kept. Only the ungraded card is discarded.")
        }
        .task {
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Words")
                    .font(AppFont.largeTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Button {
                    app.startReview(scopeID: preferences.selectedStackID)
                } label: {
                    Text("\(summary.saved) saved · \(dueCount) due today")
                        .font(AppFont.font(13, .regular))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dueCount > 0 ? "Review \(dueCount) due cards" : "No cards due today")
                .accessibilityIdentifier("words.due")
            }
            Spacer(minLength: 4)
            Menu {
                Button("Review due cards") {
                    app.startReview(scopeID: preferences.selectedStackID)
                }
                Button("Stacks") { app.router.push(.stacks) }
                Button("Settings") { app.router.push(.settings) }
                Button("Widgets") { app.router.push(.widgets) }
                Divider()
                Button {
                    app.preferences.preferences.filter = preferences.filter == .difficult ? .all : .difficult
                } label: {
                    Text(LocalizedStringKey(preferences.filter == .difficult ? "Show all words" : "Difficult words"))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColor.surface))
                    .overlay(Circle().stroke(AppColor.divider, lineWidth: 1))
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("words.more")

            CircleIconButton(systemName: "plus", accessibilityLabel: "Add word", filled: true) {
                app.router.presentEditor(.new(stackID: preferences.selectedStackID ?? app.library.defaultStack()?.id))
            }
            .accessibilityIdentifier("words.add")
        }
    }

    private func activeSessionBanner(_ session: ReviewSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.accentStrong)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unfinished review")
                    .font(AppFont.font(14, .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(app.review.totalReviewed(session)) answered · \(app.review.distinctCount(session)) in session")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button("Resume") {
                app.router.reviewLaunch = ReviewLaunch(id: session.id)
            }
            .font(AppFont.font(13, .semibold))
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(AppColor.accentStrong))
            .accessibilityIdentifier("words.review.resume")
            Button("End") { pendingEndSession = session }
                .font(AppFont.font(13, .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(height: 36)
        }
        .padding(14)
        .raisedSurface(radius: 16)
    }

    // MARK: Compact

    @ViewBuilder
    private func compactContent(width: CGFloat) -> some View {
        if width >= 440 {
            DueHero(due: dueCount, total: summary.saved, label: scopeName) {
                app.startReview(scopeID: preferences.selectedStackID)
            }
        } else {
            statCards
        }
        searchAndFilters
        wordListSurface
    }

    private var statCards: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    StatCard(count: summary.new, label: "New", accessibilityIdentifier: "words.stat.new")
                    StatCard(count: summary.learning, label: "Learning", accessibilityIdentifier: "words.stat.learning")
                    StatCard(count: summary.learned, label: "Learned", accessibilityIdentifier: "words.stat.learned")
                }
            } else {
                HStack(spacing: 11) {
                    StatCard(count: summary.new, label: "New", accessibilityIdentifier: "words.stat.new")
                    StatCard(count: summary.learning, label: "Learning", accessibilityIdentifier: "words.stat.learning")
                    StatCard(count: summary.learned, label: "Learned", accessibilityIdentifier: "words.stat.learned")
                }
            }
        }
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(placeholder: "Search words", text: $searchText)
            FlowLayout(spacing: 7) {
                ForEach([CardFilter.all, .learning, .learned, .new]) { filter in
                    FilterChip(
                        title: filter.title,
                        count: filter == .all ? summary.saved : categories.first(where: { $0.filter == filter })?.count,
                        isSelected: preferences.filter == filter,
                        action: { select(filter) }
                    )
                }
            }
            if preferences.filter == .difficult {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Difficult filter is on")
                        .font(AppFont.font(12, .semibold))
                    Spacer()
                    Button("Show all") { select(.all) }
                        .font(AppFont.font(12, .semibold))
                        .foregroundStyle(AppColor.accentStrong)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(AppColor.accentInk)
                .padding(.horizontal, 12)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var wordListSurface: some View {
        GroupedSurface {
            if displayedCards.isEmpty {
                if summary.saved == 0 {
                    EmptyStateView(
                        title: "Your word list is empty",
                        message: "Save a word and its translation to start practicing.",
                        actionTitle: "Add your first word",
                        action: {
                            app.router.presentEditor(.new(stackID: preferences.selectedStackID ?? app.library.defaultStack()?.id))
                        }
                    )
                    .accessibilityIdentifier("words.empty")
                } else {
                    EmptyStateView(
                        title: searchText.isEmpty ? "No words here" : "No matches",
                        message: searchText.isEmpty
                            ? "Try another filter or stack."
                            : "Try a different spelling or clear the search.",
                        actionTitle: "Reset filters",
                        action: resetFilters
                    )
                    .accessibilityIdentifier("words.empty.results")
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedCards.enumerated()), id: \.element.id) { index, card in
                        WordRow(card: card) {
                            app.router.presentEditor(.edit(card.id))
                        }
                        .accessibilityIdentifier("words.row")
                        if index < displayedCards.count - 1 {
                            SettingsDivider(inset: 72)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("words.list")
    }

    // MARK: Expanded

    @ViewBuilder
    private func expandedContent(width: CGFloat, mode: AppMetrics.LayoutMode) -> some View {
        let gap = mode.gap
        let leftWidth = mode == .duo
            ? min(mode.leftWidth, max(200, width * 0.35))
            : min(mode.leftWidth, max(240, width * 0.36))
        HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .leading, spacing: 14) {
                searchAndFilters
                wordListSurface
            }
            .frame(width: leftWidth)

            VStack(alignment: .leading, spacing: 16) {
                DueHero(
                    due: dueCount,
                    total: summary.saved,
                    label: scopeName,
                    ringSize: mode == .pad ? 150 : 130
                ) {
                    app.startReview(scopeID: preferences.selectedStackID)
                }
                HStack(spacing: 11) {
                    StatCard(count: summary.new, label: "New")
                    StatCard(count: summary.learning, label: "Learning")
                    StatCard(count: summary.learned, label: "Learned")
                }
                SectionHeader(title: "Categories")
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(categories) { category in
                        CategoryTile(
                            summary: category,
                            total: summary.saved,
                            isSelected: preferences.filter == category.filter
                        ) {
                            select(category.filter)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func select(_ filter: CardFilter) {
        app.preferences.preferences.filter = filter
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resetFilters() {
        searchText = ""
        app.preferences.preferences.filter = .all
        app.preferences.preferences.selectedStackID = app.library.defaultStack()?.id
    }
}

struct ReviewScopePickerView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    let picker: ScopePickerState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose one stack for this session. Each stack keeps its own limits and learning rules.")
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textSecondary)
                    GroupedSurface {
                        ForEach(Array(picker.stacks.enumerated()), id: \.element.id) { index, stack in
                            Button {
                                dismiss()
                                app.preferences.preferences.selectedStackID = stack.id
                                app.startReview(scopeID: stack.id)
                            } label: {
                                HStack(spacing: 12) {
                                    InitialTile(word: stack.name, id: stack.id, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stack.name)
                                            .font(AppFont.fieldValue())
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text("\(stack.savedCount) saved · \(stack.dueCount) due")
                                            .font(AppFont.caption())
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(AppColor.textMuted)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < picker.stacks.count - 1 { SettingsDivider(inset: 68) }
                        }
                    }
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle("Review due cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
